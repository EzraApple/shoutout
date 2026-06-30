# ShoutOut

<p align="center">
  <img src="docs/assets/shoutout-icon.png" alt="ShoutOut app icon: a blue crab mascot wearing headphones and a boom microphone" width="180">
</p>

ShoutOut is a small local-first macOS dictation app with a tiny wall-crawling crab mascot. Hold your shortcut, speak, release, and it pastes cleaned-up text into the app you were already using.

I built it around the voice loop I wanted for everyday writing: quick global shortcut capture, microphone recording, swappable on-device transcription engines, lightweight cleanup, focused-app paste, and WPM stats.

The app stays intentionally small: no cloud transcription service, no account system, and no extra editor to manage. The little crab waits on the edge of the screen, pops into boom-mic mode while listening, and shows a tiny spinner while text is being generated.

## Download

Download the signed Mac app from [shoutout.sh](https://shoutout.sh/). The public build is a notarized Apple-silicon DMG and updates through Sparkle.

## Developer Setup

Prerequisites:

- macOS 15 or newer.
- Xcode or Command Line Tools with Swift 6. Swift 6.2+ is needed to build the macOS 26 Apple Dictation path.
- Node.js 22.12 or newer for the website.

```bash
git clone git@github.com:EzraApple/shoutout.git
cd shoutout
make build
make restart-local
```

`make restart-local` rebuilds the Swift package, replaces `~/Applications/ShoutOut.app`, skips onboarding, preserves existing macOS permissions, and opens the app. For a first-run local install with onboarding and permission prompts enabled, use:

```bash
make install-local
```

Run the main validation commands before pushing app changes:

```bash
make test
make test-language-pass
make web-build
```

For website-only work:

```bash
npm --prefix apps/web install
make web-dev
```

Website analytics are PostHog-only and scoped to the public site, not the Mac app. Session replay is enabled for the site with all inputs masked. The Vercel project needs these environment variables set to the same PostHog website project:

```bash
VITE_POSTHOG_KEY=phc_...
VITE_POSTHOG_HOST=https://us.i.posthog.com
POSTHOG_PROJECT_API_KEY=phc_...
POSTHOG_HOST=https://us.i.posthog.com
```

The site captures pageviews, section views, navigation clicks, download clicks, download redirect starts, outbound link clicks, setup checklist interactions, and demo chat submissions. The `/download` redirect receives the anonymous browser PostHog ID from the client when available, so `download clicked` and `download started` can be joined in PostHog funnels.

The repo is organized as a small monorepo:

```text
apps/macos/  ShoutOut Swift package and app bundle scripts
apps/web/    Vite site for shoutout.sh
docs/        implementation notes and release checklists
scripts/     repo-level install and test helpers
```

The app is a Swift Package under `apps/macos/`. The core post-processing, insertion formatting, cleanup validation, history, and stats logic live in the `ShoutOutCore` target and are covered by XCTest.

### Permissions

On first launch, grant these in System Settings -> Privacy & Security:

- Microphone, so ShoutOut can record your voice.
- Speech Recognition, if you use Apple Speech or Apple Dictation.
- Accessibility, so it can paste text into the focused app.
- Input Monitoring, so it can detect the global shortcut while another app is focused.

If permissions, audio input, or paste behavior gets stuck, see [TROUBLESHOOTING.md](TROUBLESHOOTING.md).

## Usage

- Hold the selected shortcut to record. Release to transcribe and paste.
- Double-tap the selected shortcut for hands-free recording. Tap it again to stop.
- Fn/Globe is the default shortcut; Settings also supports Option Space, Command Shift Space, and Control Space.
- Click the menu bar waveform icon for Settings and today’s word/WPM/latency count.
- Pick WhisperKit, Apple Speech, or Apple Dictation in Settings -> Transcription. WhisperKit is the current default.
- Toggle formatting cleanup for filler words, spoken punctuation, and smart insertion spacing.
- Smart insertion uses focused-field context for spacing and conservative mid-sentence casing.
- Smart spacing falls back to a trailing space when focused-field context is unavailable.
- Toggle “Dim system audio while recording” if you want music lowered during dictation and restored afterward.

## Engines And Models

WhisperKit is the current default engine. It uses local Core ML models and gives the most model control, at the cost of a first-use download and more startup time.

Apple Speech uses Apple’s built-in Speech framework with `requiresOnDeviceRecognition`, so it fails closed instead of sending audio to cloud recognition. On macOS 26+, recordings longer than about 15 seconds are routed to Apple Dictation, which uses SpeechAnalyzer and the long-dictation transcriber path instead of the older one-request recognizer.

Apple Dictation is only available when running on macOS 26+ and building with Swift 6.2+ tools. Older systems still build and run with Apple Speech and WhisperKit.

WhisperKit models download on first use and run locally through WhisperKit/Core ML.

| Model | Size | Use |
| --- | ---: | --- |
| Large v3 Turbo 626 MB | ~626 MB | Current default balance of quality and speed |
| Large v3 Turbo 632 MB | ~632 MB | Benchmark candidate for comparing quality and speed |
| Fast English | smaller | Faster English-only fallback with a quality tradeoff |

Model data is stored in `~/Library/Application Support/com.ezraapple.shoutout/Models/`.

## Development

Each successful dictation records local performance metrics, including Fn-to-recording latency, stop-to-paste latency, transcription wall time, first-token timing, real-time factor, and speed factor. These show up in Settings and in `~/Library/Logs/ShoutOut/runtime.log` as `dictation metrics ...`.

## Release Prep

The public download path is a Developer ID signed and notarized DMG. The release script is wired through:

```bash
make release-preflight
make release-dmg
make sparkle-appcast
make blob-upload-dmg
vercel --prod
```

The release machine needs:

- A `Developer ID Application` certificate in Keychain.
- A private `.env` copied from `.env.example` with `CODE_SIGN_IDENTITY` and `NOTARY_PROFILE`.
- A Keychain notary profile created with `xcrun notarytool store-credentials`.
- A Sparkle EdDSA update key. Run `make sparkle-public-key`, paste the printed `SUPublicEDKey` value into `SPARKLE_PUBLIC_ED_KEY`, and keep the private key in Keychain.

Release builds inject the Sparkle public key into `Info.plist`; local builds without `SPARKLE_PUBLIC_ED_KEY` keep the updater disabled. `make sparkle-appcast` signs `dist/sparkle/appcast.xml` from the notarized DMG and stages it into `apps/web/public/appcast.xml` with the DMG in `apps/web/public/releases/`, so a site deploy serves the configured Sparkle URLs.

Release builds default to the current Mac architecture; the public appcast currently declares `arm64`. The release QA checklist lives in [docs/release/dmg-readiness-checklist.md](docs/release/dmg-readiness-checklist.md).

## License

ShoutOut is released under the MIT license. See `LICENSE`.
