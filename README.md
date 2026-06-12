# Shout Out

Local-first macOS dictation. Hold Fn, speak, release, and Shout Out pastes cleaned-up text into the app you were already using.

Shout Out is built for the narrow Wispr Flow loop: global Fn/Globe capture, microphone recording, on-device WhisperKit transcription, dictionary-aware cleanup, focused-app paste, and lightweight WPM stats.

## Install

Prerequisite: Xcode 16 or a working Swift 6 Command Line Tools install.

```bash
git clone git@github.com:EzraApple/shout-out.git
cd shout-out
make install
```

`make install` builds `Shout Out.app`, copies it into `~/Applications`, and opens it.

On first launch, grant:

- Microphone, so Shout Out can record your voice.
- Accessibility, so it can paste text into the focused app.
- Input Monitoring, so it can detect Fn/Globe while another app is focused.

If macOS does not show a prompt, open System Settings → Privacy & Security and enable Shout Out under those three sections.

## Usage

- Hold Fn/Globe to record. Release to transcribe and paste.
- Double-tap Fn/Globe for hands-free recording. Tap Fn/Globe again to stop.
- Click the menu bar waveform icon for Settings and today’s word/WPM count.
- Add custom dictionary entries in Settings. The default dictionary includes `Yuxin` with aliases like `yu xin`, `you shin`, and `Y-U-X-I-N`.
- Toggle “Dim system audio while recording” if you want music lowered during dictation and restored afterward.

## Models

Whisper models download on first use and run locally through WhisperKit/Core ML.

| Model | Size | Use |
| --- | ---: | --- |
| tiny | ~75 MB | Fast debugging |
| base | ~142 MB | Fast everyday transcription |
| small | ~466 MB | Better accuracy |
| medium | ~1.5 GB | High accuracy |
| large-v3-v20240930_626MB | ~626 MB | Recommended balance |

Model data is stored in `~/Library/Application Support/com.ezraapple.shoutout/Models/`.

## Development

```bash
make test
make build
make run
```

The app is a Swift Package under `macos/`. The core dictionary, post-processing, and stats logic live in the `ShoutOutCore` target and are covered by XCTest.

## Attribution

Shout Out is based on the MIT-licensed Inputalk macOS dictation app by the Inputalk contributors. The original license is retained in `LICENSE`. Transcription is powered by WhisperKit.
