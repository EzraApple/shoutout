# ShoutOut

<p align="center">
  <img src="docs/assets/shoutout-icon.png" alt="ShoutOut's crab mascot" width="140">
</p>

**English dictation, right where you’re typing.**

ShoutOut is a free, local-first macOS dictation app. Hold **Fn/Globe**, speak, and release to paste into your current app. Double-tap for hands-free recording.

[Website & download](https://shoutout.sh) · [Development](docs/development.md) · [Troubleshooting](TROUBLESHOOTING.md)

## A few things that make it ShoutOut

- **On your Mac.** Transcription and text cleanup run locally. No account required.
- **Less waiting.** Speech recognition starts while you talk, before you release the shortcut.
- **Your words, tidied up.** Optional cleanup with Normal, Casual, and Formal tones.
- **Easy to find again.** Searchable local transcription history with one-click copy.
- **Your spelling.** A customizable dictionary for names, acronyms, and common mishearings.
- **Make it yours.** Choose Glass, Classic, or an animated Crab recording indicator, with a shared color theme for the app.

Requires **Apple Silicon and macOS 15 or later**. Dictation downloads one **731 MB** speech model. Optional text cleanup downloads a separate model. Onboarding walks you through Microphone, Accessibility, and Input Monitoring permissions.

## Customization

In **Settings → Make it yours**, choose an **Indicator** to suit your desktop:

- **Glass:** a translucent recording indicator with an animated loading rim.
- **Classic:** a compact recording indicator with a waveform and spinner.
- **Crab:** an animated companion that walks along the edge of your screen.

Choose an **App theme** to change the crab, app icon, and indicator accent colors. You can also change the recording shortcut here.

## Development

The app is a Swift package in [`apps/macos`](apps/macos); the website lives in [`apps/web`](apps/web).

After [setting up the build tools](docs/development.md), run from the repo root:

```sh
make run       # Build and open the app
make test      # Run Swift tests and repo checks
make web-dev   # Start the website dev server
```

See the [development guide](docs/development.md) for prerequisites, local QA, models, and release workflows.

## Dictionary

Open **Dictionary** in the app sidebar and choose **Add Entry**. Enter what ShoutOut hears under **Replace** and your preferred spelling under **Write as**. Separate multiple variations with commas or new lines. You can search, edit, delete, and test your saved entries on the same page.

Replacements match whole phrases without regard to capitalization. Longer phrases win when matches overlap. Each replacement runs once, before optional AI cleanup, with every transcription engine. Cleanup can then apply your writing style, including capitalization. Your dictionary is saved locally in `dictionary.json` alongside the app’s other local data.

## License

No open-source license is granted for the source code or project files.
