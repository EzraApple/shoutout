use std::collections::HashSet;
use std::env;
use std::error::Error;
use std::fs::{self, File};
use std::io::{self, BufRead, BufReader, BufWriter, Read, Write};
use std::path::{Path, PathBuf};

use base64::Engine as _;
use base64::engine::general_purpose::STANDARD as BASE64;
use serde::Deserialize;
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use transcribe_cpp::{
    Backend, DeviceType, Model, ModelOptions, RunOptions, Session, SessionOptions,
    StreamOptions, TimestampKind,
};

const MODEL_FILE: &str = "parakeet-unified-en-0.6b-Q8_0.gguf";
const MODEL_SHA256: &str = "4b50b6dd862bf6e346929aaf4f5eaacec003bfa3f56462d6c874b41ef2f38795";
const MODEL_BYTES: u64 = 731_357_568;
const MODEL_ARCH: &str = "parakeet";
const MODEL_VARIANT: &str = "unified-en-0.6b";
const SAMPLE_RATE: usize = 16_000;
const MINIMUM_AUDIO_SAMPLES: usize = SAMPLE_RATE * 3 / 2;
const TRAILING_SILENCE_SAMPLES: usize = SAMPLE_RATE / 5;
const MAX_AUDIO_SAMPLES: usize = SAMPLE_RATE * 60 * 10;
const MAX_LINE_BYTES: usize = 64 * 1024 * 1024;

type AnyResult<T> = Result<T, Box<dyn Error + Send + Sync>>;

#[derive(Deserialize)]
#[serde(tag = "op", rename_all = "lowercase")]
enum Request {
    Begin { id: String },
    Feed { id: String, audio: String },
    Finish { id: String },
    Cancel { id: String },
    Transcribe { id: String, audio: String },
}

impl Request {
    fn id(&self) -> &str {
        match self {
            Self::Begin { id }
            | Self::Feed { id, .. }
            | Self::Finish { id }
            | Self::Cancel { id }
            | Self::Transcribe { id, .. } => id,
        }
    }
}

enum Input {
    End,
    Request(Request),
    Invalid { id: Option<String>, message: String },
}

struct Worker {
    model: Model,
    session: Option<Session>,
    session_options: SessionOptions,
    batch_options: RunOptions,
    stream_options: RunOptions,
    stream_config: StreamOptions,
    stream_available: bool,
    max_audio_samples: Option<usize>,
    used_ids: HashSet<String>,
}

fn main() {
    let model_path = match parse_model_path() {
        Ok(path) => path,
        Err(error) => {
            let _ = write_stdout(&json!({"event":"error", "status":"error", "message":error.to_string(), "error":error.to_string()}));
            std::process::exit(2);
        }
    };
    let mut worker = match Worker::load(&model_path) {
        Ok(worker) => worker,
        Err(error) => {
            eprintln!("hex speech worker initialization failed: {error}");
            let _ = write_stdout(&json!({"event":"error", "status":"error", "message":error.to_string(), "error":error.to_string()}));
            std::process::exit(2);
        }
    };
    let stdin = io::stdin();
    let stdout = io::stdout();
    let mut input = BufReader::new(stdin.lock());
    let mut output = BufWriter::new(stdout.lock());
    if let Err(error) = write_response(&mut output, &json!({
        "event":"ready", "status":"ready", "model":MODEL_FILE,
        "modelSha256":MODEL_SHA256, "backend":"metal",
        "runtime":"transcribe-cpp=0.2.4", "streamAvailable":worker.stream_available
    })) {
        eprintln!("could not write ready response: {error}");
        std::process::exit(1);
    }
    if let Err(error) = worker.serve(&mut input, &mut output) {
        eprintln!("hex speech worker protocol stopped: {error}");
        std::process::exit(1);
    }
}

impl Worker {
    fn load(path: &Path) -> AnyResult<Self> {
        prioritize_inference_thread();
        verify_model(path)?;
        transcribe_cpp::disable_logging();
        let model = Model::load_with(path, &ModelOptions { backend: Backend::Metal, device: None })?;
        let device = model.device()?;
        if device.kind != "metal" || !matches!(device.device_type, DeviceType::Gpu | DeviceType::Igpu) {
            return Err(format!("expected a Metal GPU, got {} ({})", device.kind, device.name).into());
        }
        if model.arch() != MODEL_ARCH || model.variant() != MODEL_VARIANT {
            return Err(format!("unexpected GGUF model {}/{}", model.arch(), model.variant()).into());
        }
        let session_options = SessionOptions { n_threads: 1, ..Default::default() };
        let batch_options = RunOptions {
            timestamps: TimestampKind::Word,
            language: Some("en".to_string()),
            ..Default::default()
        };
        let stream_options = RunOptions {
            timestamps: TimestampKind::Segment,
            ..batch_options.clone()
        };
        let stream_config = StreamOptions::default();
        let max_audio_samples = usize::try_from(model.capabilities().max_audio_ms)
            .ok().filter(|maximum| *maximum > 0).and_then(|maximum| maximum.checked_mul(16));

        let mut session = model.session_with(&session_options)?;
        session.run(&vec![0.0; MINIMUM_AUDIO_SAMPLES], &batch_options)?;
        drop(session);
        let mut session = model.session_with(&session_options)?;
        let stream_available = if model.capabilities().supports_streaming {
            match session.stream(&stream_options, &stream_config) {
                Ok(mut stream) => match stream.feed(&vec![0.0; SAMPLE_RATE]).and_then(|_| stream.finalize()) {
                    Ok(_) => true,
                    Err(error) => {
                        eprintln!("stream probe failed: {error}");
                        false
                    }
                },
                Err(error) => {
                    eprintln!("stream probe failed: {error}");
                    false
                }
            }
        } else {
            false
        };
        drop(session);
        let session = Some(model.session_with(&session_options)?);
        eprintln!("hex speech worker loaded {} on {} (stream={stream_available})", MODEL_FILE, device.name);
        Ok(Self {
            model, session, session_options, batch_options, stream_options,
            stream_config, stream_available, max_audio_samples, used_ids: HashSet::new(),
        })
    }

    fn serve<R: BufRead, W: Write>(&mut self, input: &mut R, output: &mut W) -> io::Result<()> {
        loop {
            match read_request(input)? {
                Input::End => return Ok(()),
                Input::Invalid { id, message } => write_error(output, id.as_deref(), &message)?,
                Input::Request(request) => {
                    let id = request.id();
                    if let Err(message) = validate_id(id) {
                        write_error(output, Some(id), &message)?;
                        continue;
                    }
                    match request {
                        Request::Begin { id } => {
                            if !self.used_ids.insert(id.clone()) {
                                write_error(output, Some(&id), "id was already used")?;
                            } else if !self.stream_available {
                                write_error(output, Some(&id), "native streaming is unavailable")?;
                            } else {
                                self.serve_stream(id, input, output)?;
                            }
                        }
                        Request::Transcribe { id, audio } => {
                            if !self.used_ids.insert(id.clone()) {
                                write_error(output, Some(&id), "id was already used")?;
                                continue;
                            }
                            match decode_audio(&audio).and_then(|samples| self.run_offline(&samples)) {
                                Ok(text) => write_result(output, &id, &text, "offline", None)?,
                                Err(error) => write_error(output, Some(&id), &error.to_string())?,
                            }
                        }
                        Request::Cancel { id } => {
                            self.used_ids.insert(id.clone());
                            write_response(output, &json!({"id":id,"event":"cancelled","status":"ok"}))?;
                        }
                        Request::Feed { id, .. } | Request::Finish { id } => {
                            write_error(output, Some(&id), "there is no active stream for this id")?;
                        }
                    }
                }
            }
        }
    }

    fn serve_stream<R: BufRead, W: Write>(&mut self, id: String, input: &mut R, output: &mut W) -> io::Result<()> {
        let Some(mut session) = self.session.take() else {
            write_error(output, Some(&id), "native session is unavailable")?;
            return Ok(());
        };
        let mut full_audio = Vec::<f32>::new();
        let mut feed_failure: Option<String> = None;
        let mut stream = match session.stream(&self.stream_options, &self.stream_config) {
            Ok(stream) => stream,
            Err(error) => {
                let message = format!("could not begin stream: {error}");
                let message = match self.restore_session() {
                    Ok(()) => message,
                    Err(reset_error) => format!("{message}; session reset failed: {reset_error}"),
                };
                write_error(output, Some(&id), &message)?;
                return Ok(());
            }
        };
        write_response(output, &json!({"id":id,"event":"begun","status":"ok"}))?;
        loop {
            match read_request(input)? {
                Input::End => return Ok(()),
                Input::Invalid { id: request_id, message } => {
                    write_error(output, request_id.as_deref(), &message)?;
                }
                Input::Request(request) => {
                    let request_id = request.id();
                    if let Err(message) = validate_id(request_id) {
                        write_error(output, Some(request_id), &message)?;
                        continue;
                    }
                    match request {
                        Request::Feed { id: feed_id, audio } if feed_id == id => {
                            let samples = match decode_audio(&audio) {
                                Ok(samples) => samples,
                                Err(error) => {
                                    drop(stream);
                                    drop(session);
                                    let message = match self.restore_session() {
                                        Ok(()) => error.to_string(),
                                        Err(reset_error) => format!("{error}; session reset failed: {reset_error}"),
                                    };
                                    write_error(output, Some(&id), &message)?;
                                    return Ok(());
                                }
                            };
                            if full_audio.len() + samples.len() > MAX_AUDIO_SAMPLES {
                                drop(stream);
                                drop(session);
                                let message = match self.restore_session() {
                                    Ok(()) => "capture exceeds the 10 minute safety limit".to_string(),
                                    Err(error) => format!("capture exceeds the 10 minute safety limit; session reset failed: {error}"),
                                };
                                write_error(output, Some(&id), &message)?;
                                return Ok(());
                            }
                            full_audio.extend_from_slice(&samples);
                            if feed_failure.is_none() && !samples.is_empty() {
                                if let Err(error) = stream.feed(&samples) {
                                    feed_failure = Some(format!("stream feed failed: {error}"));
                                }
                            }
                            write_response(output, &json!({
                                "id":id,"event":"fed","status":"ok","samples":samples.len()
                            }))?;
                        }
                        Request::Finish { id: finish_id } if finish_id == id => {
                            let stream_text = if full_audio.is_empty() {
                                Err("capture contained no audio".to_string())
                            } else if let Some(reason) = feed_failure {
                                Err(reason)
                            } else {
                                match stream.finalize() {
                                    Ok(_) => {
                                        let text = stream.text().full.trim().to_string();
                                        if text.is_empty() { Err("stream returned no text".to_string()) }
                                        else { Ok(text) }
                                    }
                                    Err(error) => Err(format!("stream finalize failed: {error}")),
                                }
                            };
                            drop(stream);
                            drop(session);
                            if let Err(error) = self.restore_session() {
                                write_error(output, Some(&id), &format!("session reset failed: {error}"))?;
                                return Ok(());
                            }
                            match stream_text {
                                Ok(text) => write_result(output, &id, &text, "stream", None)?,
                                Err(reason) if !full_audio.is_empty() => {
                                    match self.run_offline(&full_audio) {
                                        Ok(text) => write_result(output, &id, &text, "fallback", Some(&reason))?,
                                        Err(error) => write_error(output, Some(&id), &format!("{reason}; offline fallback failed: {error}"))?,
                                    }
                                }
                                Err(reason) => write_error(output, Some(&id), &reason)?,
                            }
                            return Ok(());
                        }
                        Request::Cancel { id: cancel_id } if cancel_id == id => {
                            drop(stream);
                            drop(session);
                            match self.restore_session() {
                                Ok(()) => write_response(output, &json!({"id":id,"event":"cancelled","status":"ok"}))?,
                                Err(error) => write_error(output, Some(&id), &format!("session reset failed: {error}"))?,
                            }
                            return Ok(());
                        }
                        Request::Cancel { id: cancel_id } => {
                            self.used_ids.insert(cancel_id.clone());
                            write_response(output, &json!({"id":cancel_id,"event":"cancelled","status":"ok"}))?;
                        }
                        other => write_error(output, Some(other.id()), "another stream is active")?,
                    }
                }
            }
        }
    }

    fn run_offline(&mut self, samples: &[f32]) -> AnyResult<String> {
        if samples.is_empty() { return Err("audio is empty".into()); }
        if samples.len() > MAX_AUDIO_SAMPLES { return Err("audio exceeds the 10 minute safety limit".into()); }
        let mut padded = samples.to_vec();
        padded.resize(padded.len().max(MINIMUM_AUDIO_SAMPLES) + TRAILING_SILENCE_SAMPLES, 0.0);
        let chunk_samples = self.max_audio_samples.unwrap_or(padded.len());
        let mut parts = Vec::new();
        for chunk in padded.chunks(chunk_samples) {
            let mut input = chunk.to_vec();
            if padded.len() > chunk_samples {
                input.resize(input.len().max(MINIMUM_AUDIO_SAMPLES), 0.0);
            }
            let text = self.run_one(&input)?;
            if !text.trim().is_empty() { parts.push(text.trim().to_string()); }
        }
        Ok(parts.join(" "))
    }

    fn run_one(&mut self, samples: &[f32]) -> AnyResult<String> {
        let mut session = self.session.take().ok_or("native session is unavailable")?;
        let result = session.run(samples, &self.batch_options);
        drop(session);
        self.session = Some(self.model.session_with(&self.session_options)?);
        Ok(result?.text)
    }

    fn restore_session(&mut self) -> AnyResult<()> {
        self.session = Some(self.model.session_with(&self.session_options)?);
        Ok(())
    }
}

fn parse_model_path() -> AnyResult<PathBuf> {
    let mut args = env::args().skip(1);
    if args.next().as_deref() != Some("--model") {
        return Err("usage: hex-speech-worker --model PATH".into());
    }
    let path = PathBuf::from(args.next().ok_or("--model needs a path")?);
    if args.next().is_some() { return Err("unexpected extra argument".into()); }
    Ok(path)
}

fn verify_model(path: &Path) -> AnyResult<()> {
    let metadata = fs::metadata(path)?;
    if metadata.len() != MODEL_BYTES {
        return Err(format!("model has {} bytes; expected {MODEL_BYTES}", metadata.len()).into());
    }
    let mut reader = BufReader::new(File::open(path)?);
    let mut digest = Sha256::new();
    let mut buffer = [0_u8; 1024 * 1024];
    loop {
        let count = reader.read(&mut buffer)?;
        if count == 0 { break; }
        digest.update(&buffer[..count]);
    }
    let actual = format!("{:x}", digest.finalize());
    if actual != MODEL_SHA256 { return Err(format!("model SHA-256 {actual} does not match the pinned artifact").into()); }
    Ok(())
}

fn decode_audio(encoded: &str) -> AnyResult<Vec<f32>> {
    let bytes = BASE64.decode(encoded)?;
    if bytes.len() % 4 != 0 { return Err("audio byte count is not divisible by four".into()); }
    if bytes.len() / 4 > MAX_AUDIO_SAMPLES { return Err("audio exceeds the 10 minute safety limit".into()); }
    let samples = bytes.chunks_exact(4)
        .map(|chunk| f32::from_le_bytes([chunk[0], chunk[1], chunk[2], chunk[3]]))
        .collect::<Vec<_>>();
    if samples.iter().any(|sample| !sample.is_finite()) { return Err("audio contains a non-finite sample".into()); }
    Ok(samples)
}

fn validate_id(id: &str) -> Result<(), String> {
    if id.is_empty() || id.len() > 128 || !id.bytes().all(|byte| byte.is_ascii_alphanumeric() || byte == b'-' || byte == b'_') {
        return Err("id must be 1 to 128 ASCII letters, digits, hyphens, or underscores".into());
    }
    Ok(())
}

fn read_request<R: BufRead>(input: &mut R) -> io::Result<Input> {
    let mut bytes = Vec::new();
    let mut too_long = false;
    loop {
        let buffer = input.fill_buf()?;
        if buffer.is_empty() {
            if bytes.is_empty() && !too_long { return Ok(Input::End); }
            break;
        }
        let newline = buffer.iter().position(|byte| *byte == b'\n');
        let count = newline.map_or(buffer.len(), |index| index + 1);
        if !too_long {
            if bytes.len() + count > MAX_LINE_BYTES { too_long = true; }
            else { bytes.extend_from_slice(&buffer[..count]); }
        }
        input.consume(count);
        if newline.is_some() { break; }
    }
    if too_long {
        return Ok(Input::Invalid { id: None, message: "JSON line exceeds 64 MiB limit".into() });
    }
    let value: Value = match serde_json::from_slice(&bytes) {
        Ok(value) => value,
        Err(error) => return Ok(Input::Invalid { id: None, message: format!("invalid JSON: {error}") }),
    };
    let id = value.get("id").and_then(Value::as_str).map(str::to_string);
    match serde_json::from_value(value) {
        Ok(request) => Ok(Input::Request(request)),
        Err(error) => Ok(Input::Invalid { id, message: format!("invalid request: {error}") }),
    }
}

fn write_stdout(value: &Value) -> io::Result<()> {
    let stdout = io::stdout();
    let mut output = BufWriter::new(stdout.lock());
    write_response(&mut output, value)
}

fn write_response<W: Write>(output: &mut W, value: &Value) -> io::Result<()> {
    serde_json::to_writer(&mut *output, value)?;
    output.write_all(b"\n")?;
    output.flush()
}

fn write_error<W: Write>(output: &mut W, id: Option<&str>, message: &str) -> io::Result<()> {
    let mut value = json!({"event":"error","status":"error","message":message,"error":message});
    if let Some(id) = id { value["id"] = json!(id); }
    write_response(output, &value)
}

fn write_result<W: Write>(output: &mut W, id: &str, text: &str, source: &str, reason: Option<&str>) -> io::Result<()> {
    let mut value = json!({"id":id,"event":"result","status":"ok","text":text,"source":source});
    if let Some(reason) = reason { value["fallbackReason"] = json!(reason); }
    write_response(output, &value)
}

#[cfg(target_os = "macos")]
fn prioritize_inference_thread() {
    const QOS_CLASS_USER_INTERACTIVE: u32 = 0x21;
    unsafe extern "C" {
        fn pthread_set_qos_class_self_np(qos_class: u32, relative_priority: i32) -> i32;
    }
    let status = unsafe { pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE, 0) };
    if status != 0 { eprintln!("could not raise inference QoS: status={status}"); }
}

#[cfg(not(target_os = "macos"))]
fn prioritize_inference_thread() {}
