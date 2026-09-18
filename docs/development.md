# Development

## macOS app

Use an Apple Silicon Mac with macOS 15 or later, Xcode with the Metal toolchain, and Swift 6.2 or newer. Check `swift --version` before building; the app’s deployment target remains macOS 15.

The asset build also needs Python 3 and Pillow. From the repository root:

```sh
python3 -m venv .venv
source .venv/bin/activate
python3 -m pip install Pillow
make run
```

`make run` builds and opens `apps/macos/dist/ShoutOut.app`. On first launch, follow onboarding to download the models and grant Microphone, Accessibility, and Input Monitoring permissions. Local builds use ad-hoc signing unless a signing identity is configured.

For repeated QA, `make restart-local` rebuilds, replaces `~/Applications/ShoutOut.app`, and reopens it with onboarding marked complete. It preserves dictation history. Use `make install-local` instead when the app should request permissions on launch. Permission and paste debugging are covered in [Troubleshooting](../TROUBLESHOOTING.md).

## Website

Use Node.js 22.12 or newer. From the repository root:

```sh
npm --prefix apps/web ci
make web-dev
```

`make web-build` runs the website’s TypeScript check and production build.

## Checks

| Command | Purpose |
| --- | --- |
| `make test` | Swift tests, package build, and repo checks |
| `make test-language-pass` | Local model cleanup smoke tests |
| `make web-build` | Website typecheck and production build |

For model comparisons and frozen audio evaluations, see the [benchmark harness](../apps/macos/Tools/DictationBenchmark/README.md) and [expanded model comparison](benchmarks/2026-09-15-expanded-models.md).

## Models and local data

English transcription uses Parakeet 1.1B, with Whisper Turbo checking suspected trailing-silence hallucinations. Optional cleanup uses Llama 3.2 1B (4-bit). Setup downloads about 5 GB; both transcription models remain loaded, so startup includes Whisper initialization.

Models and history live under `~/Library/Application Support/com.ezraapple.shoutout/`. Transcription models use `Models/`; cleanup models use `LanguageModels/`. Keep private dictation evaluation data in the Git-ignored `.local-evals/` directory.

## Mascot assets

Canonical art lives in [`assets/mascot`](../assets/mascot). `scripts/sync-mascot-assets.py` derives the website sprites, macOS sprites, color variants, and app icons. It runs as part of `make build`; use `make sync-assets` when working on assets alone. Keep sprite canvas sizes fixed to avoid jumps between walking and recording states.

## Releases

Follow the [app-update workflow](../.agents/skills/shoutout-app-update/SKILL.md) for version metadata, signing, notarization, uploads, and live verification. Releases currently target arm64.

The release machine needs a Developer ID Application certificate, a working notarization profile, Vercel Blob access, and a Sparkle EdDSA key. Start with `make release-preflight`. `make sparkle-public-key` prints the public key for build configuration; builds without `SPARKLE_PUBLIC_ED_KEY` have updates disabled.

The workflow uses `UNIVERSAL=false make release-dmg`, `make blob-upload-dmg`, and `make sparkle-appcast`. Follow the full workflow so the downloadable DMG, appcast, website, and version metadata agree before publishing.
