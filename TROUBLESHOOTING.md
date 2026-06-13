# Troubleshooting

This document is mostly for agents and operators debugging a local setup. If you are just trying to install and use Shout Out, start with the setup flow in [README.md](README.md).

## Permissions Look Granted But Hotkey Still Fails

If Accessibility or Input Monitoring is checked in System Settings but Shout Out still shows it as missing, reset the stale macOS privacy rows and reinstall:

```bash
make reset-permissions
make install
```

Then open System Settings → Privacy & Security and grant:

- Microphone
- Accessibility
- Input Monitoring

## AirPods Or Bluetooth Mic Records Silence

If Shout Out shows `No speech` or inserts nothing while permissions are granted, first check the selected input device:

1. Open System Settings → Sound → Input.
2. Select the microphone you expect Shout Out to use.
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
model ready
```

During recording, `record started elapsedMs=...` shows hotkey-to-audio startup time.
