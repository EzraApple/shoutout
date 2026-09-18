# ShoutOut

<p align="center">
  <img src="docs/assets/shoutout-icon.png" alt="ShoutOut's crab mascot" width="140">
</p>

**English dictation, right where you’re typing.**

ShoutOut is a local-first macOS dictation app. Hold **Fn/Globe**, speak, and release to paste into your current app. Double-tap for hands-free recording.

[Website & download](https://shoutout.sh) · [Development](docs/development.md) · [Troubleshooting](TROUBLESHOOTING.md)

## A few things that make it ShoutOut

- **On your Mac.** Transcription and text cleanup run locally. No account required.
- **Your words, tidied up.** Optional cleanup with Normal, Casual, and Formal tones.
- **Easy to find again.** Searchable local transcription history with one-click copy.
- **A little personality.** A wall-walking crab in your choice of color, or a simple Classic recording indicator.

Requires **Apple Silicon and macOS 15 or later**. First setup downloads about **5 GB** of models. Onboarding walks you through Microphone, Accessibility, and Input Monitoring permissions.

## Development

The app is a Swift package in [`apps/macos`](apps/macos); the website lives in [`apps/web`](apps/web).

After [setting up the build tools](docs/development.md), run from the repo root:

```sh
make run       # Build and open the app
make test      # Run Swift tests and repo checks
make web-dev   # Start the website dev server
```

See the [development guide](docs/development.md) for prerequisites, local QA, models, and release workflows.

## License

No open-source license is granted for the source code or project files.
