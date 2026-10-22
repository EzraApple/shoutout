# Development

## macOS app

Use an Apple Silicon Mac with macOS 15 or later, Xcode with the Metal toolchain, and Swift 6.2 or newer. Check `swift --version` before building; the app’s deployment target remains macOS 15.

The asset build also needs Python 3 and Pillow. Fetch the frozen Mini assets once, then point `MINI_CLEANUP_ASSET_DIR` at that directory. The download and each asset have pinned hashes. The app builder copies only `mini-fixed256.mlpackage`, `vocab.txt`, and `tokenizer-config.json`; users receive them inside the app. From the repository root:

```sh
python3 -m venv .venv
source .venv/bin/activate
python3 -m pip install Pillow
python3 apps/macos/scripts/mini-assets.py fetch "$PWD/.local-evals/mini-assets"
export MINI_CLEANUP_ASSET_DIR="$PWD/.local-evals/mini-assets"
make run
```

`make run` builds and opens `apps/macos/dist/ShoutOut.app`. On first launch, follow onboarding to download the models and grant Microphone, Accessibility, and Input Monitoring permissions. Local builds use ad-hoc signing unless a signing identity is configured.

For repeated QA, `make restart-local` rebuilds, replaces `~/Applications/ShoutOut.app`, and reopens it with onboarding marked complete. It preserves dictation history. Use `make install-local` instead when the app should request permissions on launch. Permission and paste debugging are covered in [Troubleshooting](../TROUBLESHOOTING.md).

A debug bundle launched with `SHOUTOUT_CLASSIC_PREVIEW=1` compares the complete Glass and Classic flows with a repeatable audio trace and Reduce Motion. It also uses the real right-edge panel, selectable as Glass or Classic. It skips capture, hotkeys, models, permissions, and the updater. Use a separate bundle identifier for the preview. Close the control window to inspect the floating panel; choose Open ShoutOut from the app menu to reopen the controls.

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

English transcription uses the 731 MB Parakeet Unified 0.6B model and processes audio as you speak. Terminal-ending checks reuse that same native model and its word timings; the normal path does not download Parakeet 1.1B or Whisper. The 0.3.0 app bundles the frozen Mini KEEP/DELETE model for optional cleanup and preserves the words it retains. It has one Text cleanup toggle and no tone rewrites. The normal app, CLI, and replay all select Mini. Existing cleanup on/off choices survive the one-time model and tone migration. Old history entries keep their original model and tone attribution. Older engines remain available to isolated CLI evaluations and may download their own models when explicitly selected.

Models and history live under `~/Library/Application Support/com.ezraapple.shoutout/`. Transcription models use `Models/`; cleanup models use `LanguageModels/`. Keep private dictation evaluation data in the Git-ignored `.local-evals/` directory.

The separate Mini trial uses `~/Library/Application Support/com.ezraapple.shoutout.mini-trial/` for settings-related local data, history, and speech models. Its cleanup model is bundled inside the trial app.

## Mascot assets

Canonical art lives in [`assets/mascot`](../assets/mascot). `scripts/sync-mascot-assets.py` derives the website sprites, macOS sprites, color variants, and app icons. It runs as part of `make build`; use `make sync-assets` when working on assets alone. Keep sprite canvas sizes fixed to avoid jumps between walking and recording states.

## Releases

Follow the [app-update workflow](../.agents/skills/shoutout-app-update/SKILL.md) for version metadata, signing, notarization, uploads, and live verification. Releases currently target arm64.

The release machine needs a Developer ID Application certificate, a working notarization profile, Vercel Blob access, and a Sparkle EdDSA key. Start with `make release-preflight`. `make sparkle-public-key` prints the public key for build configuration; builds without `SPARKLE_PUBLIC_ED_KEY` have updates disabled.

The workflow uses `SHOUTOUT_DMG_HEADLESS=true UNIVERSAL=false make release-dmg`, `make blob-upload-dmg`, and `make sparkle-appcast`. Follow the full workflow so the downloadable DMG, appcast, website, and version metadata agree before publishing.
