# ShoutOut

<p align="center">
  <img src="docs/assets/shoutout-icon.png" alt="ShoutOut app icon: a blue crab mascot wearing headphones and a boom microphone" width="180">
</p>

ShoutOut is a local-first macOS dictation app with a small wall-crawling crab mascot. Hold the shortcut, speak, release, and ShoutOut transcribes locally, cleans the text conservatively, then pastes into the app you were already using.

This README is product and operator context for the repo. Keep public download and install copy on the website, not here.

## Current Product

- Global shortcut recording with hold-to-talk and double-tap hands-free modes.
- Fn/Globe as the default shortcut, with Option Space, Command Shift Space, and Control Space available in Settings.
- Local transcription through WhisperKit by default, with Apple Speech and Apple Dictation paths still available.
- Writing cleanup for filler words, repeats, false starts, and the selected tone: Normal, Casual, or Formal.
- Smart paste formatting that uses focused-field context for spacing, capitalization, and punctuation, then falls back safely when context is unavailable.
- Local history, word counts, WPM, latency metrics, and cleanup trace details.
- A color-selectable crab mascot with idle walking frames, wall-traversal frames, and a boom-mic recording animation that enters, holds still while recording, and exits before walking resumes.
- Sparkle app updates for signed release builds.

The app has no account system and no cloud transcription service in the normal product path. WhisperKit model files and language cleanup model files live under the user's Application Support directory.

## App Surfaces

- Menu bar waveform: opens the main popover and shows today's dictation stats.
- Home: compact dashboard, current shortcut state, and recent performance.
- History: local transcription history with cleanup status, before/after text when cleanup changed content, plain-English reason copy, selected tone, and timing.
- Settings: shortcut, engine, model, mascot color, app icon color, writing cleanup, paste formatting, audio dimming, and advanced diagnostics.
- Mascot overlay: edge-of-screen crab that walks when idle, switches to the boom-mic recording sequence while listening, and avoids changing scale between states.

## Dictation Pipeline

1. The hotkey manager detects the selected shortcut while another app is focused.
2. The recorder starts audio capture and logs press-to-record latency.
3. Very short or low-signal recordings are discarded instead of pasted.
4. The selected transcription engine returns text locally.
5. Optional mechanical cleanup removes simple filler and obvious repeated starts before the model pass.
6. The local language cleanup pass may apply the selected tone while preserving meaning and meaningful words.
7. Validation accepts conservative cleanup or keeps the original transcript.
8. Smart insertion formats spacing, casing, and trailing punctuation against the focused text field.
9. Text is pasted through the focused app path, then history and metrics are recorded.

## Art And Mascot System

The current visual source is the cute navy-blue crab from `docs/assets/shoutout-icon.png`: round shell, chunky claws, dark teal headphones, small happy face, and a dark boom microphone.

Canonical generated art lives under `assets/mascot/`:

- `idle-walk/`: normal crab with no boom microphone.
- `recording-boom/`: boom microphone assets for listening states.
- `generated-candidates/crab-boom-pet-sheet-v4-alpha.png`: current wall recording sprite source.

`scripts/sync-mascot-assets.py` derives the web sprites, macOS sprite resources, wall-traversal frames, recording intro frames, recording hold frame, app icon variants, and mascot color variants from those sources. The app resources intentionally preserve fixed canvas sizes so changing the boom animation does not resize the crab, shift the wall position, or introduce transparent-frame flicker.

## Local Workflows

The useful repo commands are:

```bash
make restart-local        # rebuild and replace ~/Applications/ShoutOut.app for local QA
make test                 # Swift tests plus repo smoke checks
make test-language-pass   # focused cleanup prompt and validation tests
make web-build            # production website build
make release-preflight    # release readiness checks
UNIVERSAL=false make release-dmg
make sparkle-appcast
make blob-upload-dmg
make sparkle-public-key
```

For website-only development, use `make web-dev`. The macOS app is a Swift Package under `apps/macos/`; the website lives under `apps/web/`; repo-level install, release, sync, and test helpers live under `scripts/`.

## Permissions

ShoutOut needs these macOS permissions:

- Microphone, to record audio.
- Speech Recognition, when using Apple Speech or Apple Dictation.
- Accessibility, to paste into the focused app.
- Input Monitoring, to detect the selected shortcut while another app is focused.

If permissions, audio input, or paste behavior gets stuck, see [TROUBLESHOOTING.md](TROUBLESHOOTING.md).

## Engines And Models

WhisperKit is the default engine. It runs local Core ML models and gives the most model control, with a first-use model download.

Apple Speech uses Apple's Speech framework with on-device recognition required. Apple Dictation is available on macOS 26+ with Swift 6.2+ tools and handles longer recordings through the newer long-dictation transcriber path.

WhisperKit model data is stored in `~/Library/Application Support/com.ezraapple.shoutout/Models/`. Language cleanup model data is stored in `~/Library/Application Support/com.ezraapple.shoutout/LanguageModels/`.

## Release Prep

Release builds are Developer ID signed, notarized, stapled, packaged as a DMG, and served through the website with a Sparkle appcast. Release builds inject the Sparkle public key into `Info.plist`; local builds without `SPARKLE_PUBLIC_ED_KEY` keep the updater disabled.

The release machine needs a `Developer ID Application` certificate, notary credentials, Vercel Blob credentials, and a Sparkle EdDSA key. The release QA checklist lives in [docs/release/dmg-readiness-checklist.md](docs/release/dmg-readiness-checklist.md).

## Source Status

Source availability and licensing are intentionally under review. Before publishing this repo publicly, reconcile this section with `LICENSE`, website copy, and release packaging.
