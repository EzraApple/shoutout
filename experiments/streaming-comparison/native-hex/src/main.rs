use std::env;
use std::error::Error;
use std::fs::{self, File};
use std::io::{BufReader, BufWriter, Read, Write};
use std::path::{Path, PathBuf};
use std::sync::mpsc;
use std::thread;
use std::time::{Duration, Instant};

use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use transcribe_cpp::{
    Backend, DeviceType, Model, ModelOptions, RunOptions, SessionOptions, StreamOptions,
    TimestampKind,
};

const HEX_COMMIT: &str = "083179900e85c1e23bb3a13591957eade092d79e";
const MODEL_SHA256: &str = "4b50b6dd862bf6e346929aaf4f5eaacec003bfa3f56462d6c874b41ef2f38795";
const MODEL_BYTES: u64 = 731_357_568;
const MODEL_NAME: &str = "parakeet-unified-en-0.6b-Q8_0.gguf";
const SAMPLE_RATE: usize = 16_000;
const MINIMUM_AUDIO_SAMPLES: usize = SAMPLE_RATE * 3 / 2;
const TRAILING_SILENCE_SAMPLES: usize = SAMPLE_RATE / 5;

type AnyResult<T> = Result<T, Box<dyn Error + Send + Sync>>;

#[derive(Deserialize)]
struct Fixture {
    name: String,
    path: PathBuf,
    reference: String,
}

struct LoadedFixture {
    fixture: Fixture,
    samples: Vec<f32>,
}

#[derive(Serialize)]
struct ResultRow<'a> {
    name: &'a str,
    path: &'a Path,
    reference: &'a str,
    text: String,
    mode: &'a str,
    source: &'a str,
    fallback_reason: Option<String>,
    audio_ms: f64,
    samples: usize,
    fed_samples: usize,
    feeds: usize,
    packet_ms: Option<usize>,
    pacing: &'a str,
    batch_ms: Option<f64>,
    release_to_text_ms: Option<f64>,
    release_to_final_ms: Option<f64>,
    session_rotation_ms: Option<f64>,
    feed_compute_ms: Option<f64>,
    finalize_compute_ms: Option<f64>,
    total_compute_ms: f64,
    hex_commit: &'static str,
    runtime: &'static str,
    backend: &'static str,
    model: &'static str,
    model_sha256: &'static str,
}

struct Settings {
    command: String,
    mode: String,
    model: PathBuf,
    manifest: Option<PathBuf>,
    output: Option<PathBuf>,
    packet_ms: usize,
    unpaced: bool,
}

enum Packet {
    Audio(Vec<f32>),
    Release(Instant),
}

struct StreamMeasure {
    text: String,
    source: &'static str,
    fallback_reason: Option<String>,
    fed_samples: usize,
    feeds: usize,
    feed_ms: f64,
    finalize_ms: f64,
    total_compute_ms: f64,
    release_to_text_ms: Option<f64>,
    release_to_final_ms: Option<f64>,
    session_rotation_ms: Option<f64>,
}

struct BatchMeasure {
    text: String,
    batch_ms: f64,
    inference_ms: f64,
}

fn main() -> AnyResult<()> {
    let settings = parse_args()?;
    prioritize_inference_thread();
    eprintln!("verifying pinned model {}", settings.model.display());
    check_model(&settings.model)?;
    eprintln!("loading Metal model");
    let model_started = Instant::now();
    transcribe_cpp::disable_logging();
    let model = Model::load_with(
        &settings.model,
        &ModelOptions { backend: Backend::Metal, device: None },
    )?;
    let device = model.device()?;
    if device.kind != "metal" || !matches!(device.device_type, DeviceType::Gpu | DeviceType::Igpu) {
        return Err(format!("expected a Metal GPU, got {} ({})", device.kind, device.name).into());
    }
    if model.arch() != "parakeet" || model.variant() != "unified-en-0.6b" {
        return Err(format!("unexpected model {}/{}", model.arch(), model.variant()).into());
    }
    let session_options = SessionOptions { n_threads: 1, ..Default::default() };
    let max_audio_samples = usize::try_from(model.capabilities().max_audio_ms)
        .ok().filter(|maximum| *maximum > 0).and_then(|maximum| maximum.checked_mul(16));
    eprintln!("max_audio_samples={}", max_audio_samples.map(|value| value.to_string()).unwrap_or_else(|| "unlimited".to_string()));
    let batch_options = RunOptions {
        timestamps: TimestampKind::Word,
        language: Some("en".to_string()),
        ..Default::default()
    };
    let stream_options = RunOptions {
        timestamps: TimestampKind::Segment,
        ..batch_options.clone()
    };
    eprintln!("model_load_ms={:.2} device={} model={}", ms(model_started.elapsed()), device.name, MODEL_NAME);

    let warm_started = Instant::now();
    eprintln!("warming offline inference");
    let mut session = model.session_with(&session_options)?;
    let silence = vec![0.0; MINIMUM_AUDIO_SAMPLES];
    session.run(&silence, &batch_options)?;
    drop(session);
    eprintln!("offline_warm_ms={:.2}", ms(warm_started.elapsed()));

    let probe_started = Instant::now();
    eprintln!("probing native stream");
    let stream_supported = model.capabilities().supports_streaming;
    let stream_config = StreamOptions::default();
    let probe_result = if stream_supported {
        probe_stream(&model, &session_options, &stream_options, &stream_config)
    } else {
        Err("the model does not advertise streaming".into())
    };
    eprintln!("stream_probe_ms={:.2} stream_available={} reason={}", ms(probe_started.elapsed()), probe_result.is_ok(), probe_result.as_ref().err().map(|e| e.to_string()).unwrap_or_default());
    if settings.command == "probe" {
        probe_result?;
        return Ok(());
    }

    let manifest = settings.manifest.as_ref().expect("run requires manifest");
    let output = settings.output.as_ref().expect("run requires output");
    let fixtures = load_fixtures(manifest)?;
    let mut writer = BufWriter::new(File::create(output)?);
    for loaded in &fixtures {
        let fixture = &loaded.fixture;
        let samples = &loaded.samples;
        let audio_ms = samples.len() as f64 * 1000.0 / SAMPLE_RATE as f64;
        let result = if settings.mode == "batch" {
            let batch = run_batch(&model, &session_options, &batch_options, samples, max_audio_samples)?;
            ResultRow {
                name: &fixture.name, path: &fixture.path, reference: &fixture.reference,
                text: batch.text, mode: "batch", source: "offline",
                fallback_reason: None, audio_ms, samples: samples.len(), fed_samples: 0,
                feeds: 0, packet_ms: None, pacing: "none", batch_ms: Some(batch.batch_ms),
                release_to_text_ms: None, release_to_final_ms: None, session_rotation_ms: None,
                feed_compute_ms: None, finalize_compute_ms: None,
                total_compute_ms: batch.inference_ms, hex_commit: HEX_COMMIT, runtime: "transcribe-cpp=0.2.4",
                backend: "Metal", model: MODEL_NAME, model_sha256: MODEL_SHA256,
            }
        } else {
            let measure = if probe_result.is_ok() {
                run_stream(&model, &session_options, &stream_options, &stream_config,
                    &batch_options, samples, max_audio_samples, settings.packet_ms, settings.unpaced)?
            } else {
                let reason = probe_result.as_ref().err().expect("probe failed").to_string();
                run_offline_fallback(&model, &session_options, &batch_options, samples,
                    max_audio_samples, reason, None, settings.unpaced)?
            };
            ResultRow {
                name: &fixture.name, path: &fixture.path, reference: &fixture.reference,
                text: measure.text, mode: "stream", source: measure.source,
                fallback_reason: measure.fallback_reason, audio_ms, samples: samples.len(),
                fed_samples: measure.fed_samples, feeds: measure.feeds,
                packet_ms: Some(settings.packet_ms),
                pacing: if settings.unpaced { "unpaced" } else { "realtime" },
                batch_ms: None, release_to_text_ms: measure.release_to_text_ms,
                release_to_final_ms: measure.release_to_final_ms,
                session_rotation_ms: measure.session_rotation_ms,
                feed_compute_ms: Some(measure.feed_ms), finalize_compute_ms: Some(measure.finalize_ms),
                total_compute_ms: measure.total_compute_ms, hex_commit: HEX_COMMIT,
                runtime: "transcribe-cpp=0.2.4", backend: "Metal", model: MODEL_NAME,
                model_sha256: MODEL_SHA256,
            }
        };
        serde_json::to_writer(&mut writer, &result)?;
        writer.write_all(b"\n")?;
        writer.flush()?;
        eprintln!("{}: {} {:.2} ms", result.name, result.source,
            result.release_to_final_ms.or(result.batch_ms).unwrap_or(result.total_compute_ms));
    }
    Ok(())
}

fn parse_args() -> AnyResult<Settings> {
    let mut args = env::args().skip(1);
    let command = args.next().ok_or("usage: native-hex-benchmark probe|run --model PATH [--mode batch|stream --manifest JSON --output JSONL] [--packet-ms N] [--unpaced-stream]")?;
    if command != "probe" && command != "run" { return Err("first argument must be probe or run".into()); }
    let mut settings = Settings { command, mode: String::new(), model: PathBuf::new(),
        manifest: None, output: None, packet_ms: 160, unpaced: false };
    while let Some(flag) = args.next() {
        match flag.as_str() {
            "--model" => settings.model = PathBuf::from(args.next().ok_or("--model needs a path")?),
            "--manifest" => settings.manifest = Some(PathBuf::from(args.next().ok_or("--manifest needs a path")?)),
            "--output" => settings.output = Some(PathBuf::from(args.next().ok_or("--output needs a path")?)),
            "--mode" => settings.mode = args.next().ok_or("--mode needs batch or stream")?,
            "--packet-ms" => settings.packet_ms = args.next().ok_or("--packet-ms needs a number")?.parse()?,
            "--unpaced-stream" => settings.unpaced = true,
            _ => return Err(format!("unknown argument {flag}").into()),
        }
    }
    if settings.model.as_os_str().is_empty() { return Err("--model is required".into()); }
    if settings.command == "run" {
        if settings.mode != "batch" && settings.mode != "stream" { return Err("--mode must be batch or stream".into()); }
        if settings.manifest.is_none() || settings.output.is_none() { return Err("--manifest and --output are required".into()); }
        if settings.packet_ms == 0 || settings.packet_ms > 1000 { return Err("--packet-ms must be 1..1000".into()); }
        if settings.mode == "batch" && settings.unpaced { return Err("--unpaced-stream requires stream mode".into()); }
    }
    Ok(settings)
}

fn check_model(path: &Path) -> AnyResult<()> {
    let metadata = fs::metadata(path)?;
    if metadata.len() != MODEL_BYTES {
        return Err(format!("model is {} bytes; expected {}", metadata.len(), MODEL_BYTES).into());
    }
    let mut reader = BufReader::new(File::open(path)?);
    let mut digest = Sha256::new();
    let mut buffer = [0_u8; 1024 * 1024];
    loop {
        let read = reader.read(&mut buffer)?;
        if read == 0 { break; }
        digest.update(&buffer[..read]);
    }
    let actual = format!("{:x}", digest.finalize());
    if actual != MODEL_SHA256 { return Err(format!("model SHA-256 {actual} does not match Hex pin").into()); }
    Ok(())
}

fn load_fixtures(path: &Path) -> AnyResult<Vec<LoadedFixture>> {
    let fixtures: Vec<Fixture> = serde_json::from_slice(&fs::read(path)?)?;
    let mut loaded = Vec::with_capacity(fixtures.len());
    for fixture in fixtures {
        let mut wav = hound::WavReader::open(&fixture.path)?;
        let spec = wav.spec();
        if spec.channels != 1 || spec.sample_rate != SAMPLE_RATE as u32 {
            return Err(format!("{} must be mono 16 kHz WAV", fixture.path.display()).into());
        }
        let samples = match (spec.sample_format, spec.bits_per_sample) {
            (hound::SampleFormat::Float, 32) => wav.samples::<f32>().collect::<Result<Vec<_>, _>>()?,
            (hound::SampleFormat::Int, bits @ (16 | 24 | 32)) => {
                let scale = (1_i64 << (bits - 1)) as f32;
                wav.samples::<i32>().map(|sample| sample.map(|value| value as f32 / scale))
                    .collect::<Result<Vec<_>, _>>()?
            }
            _ => return Err(format!("unsupported WAV format in {}", fixture.path.display()).into()),
        };
        if samples.is_empty() || samples.iter().any(|s| !s.is_finite()) {
            return Err(format!("invalid audio in {}", fixture.path.display()).into());
        }
        loaded.push(LoadedFixture { fixture, samples });
    }
    Ok(loaded)
}

fn probe_stream(model: &Model, session_options: &SessionOptions, run_options: &RunOptions,
    stream_options: &StreamOptions) -> AnyResult<()> {
    let mut session = model.session_with(session_options)?;
    let mut stream = session.stream(run_options, stream_options)?;
    stream.feed(&vec![0.0; SAMPLE_RATE])?;
    stream.finalize()?;
    Ok(())
}

fn run_batch(model: &Model, session_options: &SessionOptions, run_options: &RunOptions,
    samples: &[f32], max_audio_samples: Option<usize>) -> AnyResult<BatchMeasure> {
    let mut padded = samples.to_vec();
    padded.resize(padded.len().max(MINIMUM_AUDIO_SAMPLES) + TRAILING_SILENCE_SAMPLES, 0.0);
    let chunk_samples = max_audio_samples.unwrap_or(padded.len());
    let mut session = model.session_with(session_options)?;
    let started = Instant::now();
    let mut inference_ms = 0.0;
    let mut text = Vec::new();
    for samples in padded.chunks(chunk_samples) {
        let mut chunk = samples.to_vec();
        if padded.len() > chunk_samples {
            chunk.resize(chunk.len().max(MINIMUM_AUDIO_SAMPLES), 0.0);
        }
        let inference_started = Instant::now();
        let transcript = session.run(&chunk, run_options)?;
        inference_ms += ms(inference_started.elapsed());
        let value = transcript.text.trim();
        if !value.is_empty() { text.push(value.to_string()); }
        drop(session);
        session = model.session_with(session_options)?;
    }
    drop(session);
    Ok(BatchMeasure { text: text.join(" "), batch_ms: ms(started.elapsed()), inference_ms })
}

fn run_stream(model: &Model, session_options: &SessionOptions, run_options: &RunOptions,
    stream_options: &StreamOptions, batch_options: &RunOptions, samples: &[f32],
    max_audio_samples: Option<usize>,
    packet_ms: usize, unpaced: bool) -> AnyResult<StreamMeasure> {
    let mut session = model.session_with(session_options)?;
    let (sender, receiver) = mpsc::channel::<Packet>();
    let mut release_time = None;
    let mut fed_samples = 0;
    let mut feeds = 0;
    let mut feed_ms = 0.0;
    let mut finalize_ms = 0.0;
    let mut release_to_text_ms = None;
    let mut stream_text = None;
    let mut failure = None;
    let packet_samples = SAMPLE_RATE * packet_ms / 1000;
    thread::scope(|scope| {
        scope.spawn(|| {
            let started = Instant::now();
            for (index, chunk) in samples.chunks(packet_samples).enumerate() {
                if !unpaced {
                    let captured = (index * packet_samples + chunk.len()) as f64 / SAMPLE_RATE as f64;
                    sleep_until(started + Duration::from_secs_f64(captured));
                }
                if sender.send(Packet::Audio(chunk.to_vec())).is_err() { return; }
            }
            if !unpaced {
                sleep_until(started + Duration::from_secs_f64(samples.len() as f64 / SAMPLE_RATE as f64));
            }
            let _ = sender.send(Packet::Release(Instant::now()));
        });
        match session.stream(run_options, stream_options) {
            Ok(mut stream) => {
                while let Ok(packet) = receiver.recv() {
                    match packet {
                        Packet::Audio(audio) => {
                            fed_samples += audio.len();
                            if failure.is_none() {
                                let started = Instant::now();
                                if let Err(error) = stream.feed(&audio) { failure = Some(error.to_string()); }
                                feed_ms += ms(started.elapsed());
                                feeds += 1;
                            }
                        }
                        Packet::Release(at) => {
                            release_time = Some(at);
                            if failure.is_none() {
                                let started = Instant::now();
                                match stream.finalize() {
                                    Ok(_) => {
                                        let snapshot = stream.text();
                                        release_to_text_ms = if unpaced { None } else {
                                            Some(ms(Instant::now().duration_since(at)))
                                        };
                                        let text = snapshot.full.trim().to_string();
                                        if text.is_empty() { failure = Some("the stream returned no text".to_string()); }
                                        else { stream_text = Some(text); }
                                    }
                                    Err(error) => failure = Some(error.to_string()),
                                }
                                finalize_ms = ms(started.elapsed());
                            }
                            break;
                        }
                    }
                }
            }
            Err(error) => {
                failure = Some(format!("could not begin stream: {error}"));
                while let Ok(packet) = receiver.recv() {
                    if let Packet::Release(at) = packet { release_time = Some(at); break; }
                }
            }
        }
    });
    let rotation_started = Instant::now();
    drop(session);
    let successor = model.session_with(session_options)?;
    let session_rotation_ms = ms(rotation_started.elapsed());
    let finished_at = Instant::now();
    drop(successor);
    if let Some(text) = stream_text {
        return Ok(StreamMeasure { text, source: "stream", fallback_reason: None,
            fed_samples, feeds, feed_ms, finalize_ms, total_compute_ms: feed_ms + finalize_ms,
            release_to_text_ms,
            release_to_final_ms: if unpaced { None } else {
                release_time.map(|at| ms(finished_at.duration_since(at)))
            },
            session_rotation_ms: Some(session_rotation_ms) });
    }
    let reason = failure.unwrap_or_else(|| "stream ended without a result".to_string());
    let mut fallback = run_offline_fallback(model, session_options, batch_options, samples,
        max_audio_samples, reason, release_time, unpaced)?;
    fallback.fed_samples = fed_samples;
    fallback.feeds = feeds;
    fallback.feed_ms = feed_ms;
    fallback.finalize_ms = finalize_ms;
    fallback.total_compute_ms += feed_ms + finalize_ms;
    fallback.session_rotation_ms = Some(session_rotation_ms);
    Ok(fallback)
}

fn run_offline_fallback(model: &Model, session_options: &SessionOptions,
    batch_options: &RunOptions, samples: &[f32], max_audio_samples: Option<usize>, reason: String,
    release_time: Option<Instant>, unpaced: bool) -> AnyResult<StreamMeasure> {
    let batch = run_batch(model, session_options, batch_options, samples, max_audio_samples)?;
    Ok(StreamMeasure { text: batch.text, source: "fallback",
        fallback_reason: Some(reason), fed_samples: 0, feeds: 0, feed_ms: 0.0,
        finalize_ms: 0.0, total_compute_ms: batch.inference_ms,
        release_to_text_ms: None,
        release_to_final_ms: if unpaced { None } else { release_time.map(|at| ms(at.elapsed())) },
        session_rotation_ms: None })
}

#[cfg(target_os = "macos")]
fn prioritize_inference_thread() {
    const QOS_CLASS_USER_INTERACTIVE: u32 = 0x21;
    unsafe extern "C" {
        fn pthread_set_qos_class_self_np(qos_class: u32, relative_priority: i32) -> i32;
    }
    let status = unsafe { pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE, 0) };
    if status == 0 {
        eprintln!("inference QoS=user-interactive");
    } else {
        eprintln!("could not raise inference QoS: status={status}");
    }
}

#[cfg(not(target_os = "macos"))]
fn prioritize_inference_thread() {}

fn sleep_until(deadline: Instant) {
    if let Some(remaining) = deadline.checked_duration_since(Instant::now()) {
        thread::sleep(remaining);
    }
}

fn ms(duration: Duration) -> f64 { duration.as_secs_f64() * 1000.0 }
