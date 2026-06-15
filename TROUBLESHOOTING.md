# Troubleshooting

This document is mostly for agents and operators debugging a local setup. If you are just trying to install and use ShoutOut, start with the setup flow in [README.md](README.md).

## Permissions Look Granted But Hotkey Still Fails

If Accessibility or Input Monitoring is checked in System Settings but ShoutOut still shows it as missing, reset the stale macOS privacy rows and reinstall:

```bash
make reset-permissions
make install
```

Then open System Settings → Privacy & Security and grant:

- Microphone
- Speech Recognition, if an Apple transcription engine is selected
- Accessibility
- Input Monitoring

## AirPods Or Bluetooth Mic Records Silence

If ShoutOut shows `No speech` or inserts nothing while permissions are granted, first check the selected input device:

1. Open System Settings → Sound → Input.
2. Select the microphone you expect ShoutOut to use.
3. Talk and confirm the input level meter moves.

Bluetooth microphones can stay selected while sending silence after route changes. If AirPods record silence, switch to the MacBook microphone or reselect/reconnect the AirPods, then try again.

The runtime log can confirm whether the app received usable audio. After a recording, look for:

```text
record signal rms=... peak=... activeRatio=...
```

If `rms` and `peak` are near zero, the selected microphone is effectively silent. If those values are nonzero but transcription is wrong, the issue is in transcription or cleanup instead.

## Runtime Logs

Runtime logs live at:

```bash
tail -f "$HOME/Library/Logs/ShoutOut/runtime.log"
```

Healthy startup lines include:

```text
permissions refresh accessibility=true inputMonitoring=true microphone=true
hotkey setup complete
model ready backend=appleSpeech
```

During recording, `record started elapsedMs=...` shows hotkey-to-audio startup time.

On macOS 26+, longer Apple Speech recordings should log `transcription autoswitch backend=appleDictation` before the transcription timing line. If that line never appears, confirm the app was built with Swift 6.2+ tools or use `make restart-local`, which automatically prefers the current Command Line Tools when they are installed.

Completed dictations also emit a single benchmark line:

```text
dictation metrics ... pressToRecordStartMs=... stopToPasteMs=... transcriptionWallMs=...
```

Use `make restart-local` after code changes to rebuild, replace the installed app, skip onboarding, and reopen ShoutOut in place.
