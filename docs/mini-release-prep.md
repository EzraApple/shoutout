# Mini 0.3.0 release

ShoutOut 0.3.0 (build 21) uses the bundled Mini KEEP/DELETE editor for optional cleanup. The app, file-transcription CLI, and replay use the same factory. The old generative validators and tone formatting do not run after Mini. Model load or inference failure keeps the input text.

A one-time migration removes legacy model and tone settings while preserving cleanup on/off, shortcuts, appearance, dictionary, and history. Older history retains its recorded model and tone attribution. Old model caches are not deleted during upgrade.

Insertion capitalizes the first word at a known sentence start and uses cursor-aware spacing. It skips obvious emails and filenames and does not add final periods or a blind trailing space. Unknown cursor context preserves the text exactly. The spoken-command pass preserves the literal word “period.” History records the intended formatted paste and keeps raw Mini output separately.

The Input Monitoring onboarding fix skips that page when access is available after granting Accessibility. Missing access keeps the page available without automatically opening System Settings.

## Build assets

Fetch the frozen export for development and CI:

```sh
python3 apps/macos/scripts/mini-assets.py fetch "$PWD/.local-evals/mini-assets"
export MINI_CLEANUP_ASSET_DIR="$PWD/.local-evals/mini-assets"
```

The archive checksum and all three asset hashes are pinned. The archive includes attribution and the upstream Apache license. Packaging copies only the model package, vocabulary, and tokenizer configuration, plus the notices from source. No transcript corpus is included. Users receive Mini inside the app and do not make a separate cleanup-model download.

For local packaging without release credentials:

```sh
SHOUTOUT_SKIP_ENV=true SKIP_NOTARIZE=true UNIVERSAL=false \
apps/macos/scripts/build-app.sh
```

For distribution, follow the [app-update workflow](../.agents/skills/shoutout-app-update/SKILL.md). Supply the existing Sparkle public key and Developer ID identity; verify the updater key and HTTPS feed in the final signed bundle.

## Release evidence

The signed arm64 app and DMG were built from `79f7c8bf0f7f`, notarized, and stapled. Both passed signature and Gatekeeper checks. The final release feed is generated from that DMG. The release PR is [#13](https://github.com/EzraApple/shoutout/pull/13).

Local checks passed 251 XCTest tests, 20 Swift Testing tests, the fixed 168-case development replay, 285 repository checks, and the website build. A packaged synthetic-speech check preserved “word period” and “auto period” through speech recognition and Mini. Public model smoke checks cover filler deletion and clean-text preservation. No weights or delete threshold changed during release preparation. The final model test was not opened.

Six onboarding scenarios previously passed with simulated permission APIs. A fresh macOS account permission-grant flow remains unverified; release work does not reset the user's permissions. Detailed local evidence is kept in the Git-ignored `.local-evals/` directory.
