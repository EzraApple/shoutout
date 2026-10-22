# Mini release preparation

This branch prepares ShoutOut 0.3.0 (build 21). It includes current main, the Mini cleanup default, the settings migration, the Input Monitoring onboarding fix, and matching website copy. It has not been published.

## App behavior

The app, headless file transcription, and replay all use the bundled Mini KEEP/DELETE editor. It removes selected source words and retains the remaining spelling, capitalization, punctuation, and order. It does not run the old Llama output validator, tone formatter, or mechanical cleanup after Mini. Text insertion handles spacing around the cursor, capitalizes the first word at a clear sentence start, and adds a final period at the end of a text field when punctuation is missing. Existing punctuation, mixed-case names, and code/URL-like text are preserved. It keeps text unchanged when cursor context is unavailable; there is no blind trailing-space fallback. The earlier spoken-command pass no longer replaces the literal word “period.” History stores the formatted intended paste text and keeps the raw Mini output separately in its cleanup trace. Model load or inference failure keeps the original text.

A one-time settings migration removes the old cleanup-model and tone choices. It preserves Text cleanup on/off, shortcuts, indicator choice, dictionary, and history. Old history keeps its original model and tone attribution. It does not delete old model caches or download a replacement cleanup model.

The onboarding fix from `839e22e` is included. After Accessibility is granted, setup resolves Input Monitoring access and skips its page if access is available. Missing access leaves that page available without automatically opening System Settings.

## Local build

Set `MINI_CLEANUP_ASSET_DIR` to the frozen export containing only the three required model assets. The builder checks their pinned hashes before clearing an old build. It stages only `mini-fixed256.mlpackage`, `vocab.txt`, and `tokenizer-config.json`; other files in the export directory are never bundled.

```sh
MINI_CLEANUP_ASSET_DIR=/absolute/path/to/frozen-export \
SHOUTOUT_SKIP_ENV=true SKIP_NOTARIZE=true UNIVERSAL=false \
apps/macos/scripts/build-app.sh
```

`SHOUTOUT_SKIP_ENV=true` skips release credentials in `.env`. Supply the existing public `SPARKLE_PUBLIC_ED_KEY` explicitly to configure the updater in a local candidate. Signing and notarization remain separate release steps. A locally verified ad-hoc build is not a notarized distributable.

## Verification and publication boundary

Local evidence is in `.local-evals/mini-release-prep-2026-10-21/verification.json` and its adjacent logs and screenshots. The app and headless DMG are in `apps/macos/dist-mini-release/`. The app is ad-hoc signed; the DMG is not notarized. Both contain the pinned Mini assets and model attribution notices.

Passed: 240 XCTest tests, 20 Swift Testing tests, 18 final focused tests, 168 exact development-output matches, 36 packaged migration combinations, and 285 repository checks. A synthetic speech test through the packaged ASR and cleanup removed a filler `like` when cleanup was enabled and kept it when disabled. An isolated app rendered the single cleanup toggle, preserved dictionary, Glass preference, and legacy history tone. The temporary QA app and its cache link were removed afterward. These are functional checks, not a new model-quality study or latency benchmark.

The sentence-formatting follow-up is recorded in `.local-evals/sentence-formatting/verification.json`. It passed 249 XCTest tests and 20 Swift Testing tests, including the unchanged 168-case Mini replay, plus the repository and website checks. It removes the implicit spoken “period” command, enables context-based initial capitalization and final periods, and removes the trailing-space fallback. No model weights or thresholds changed. This follow-up rebuilds the local app and DMG; the installed trial stays unchanged.

Checks cover the release Swift tests, migration, the 168 authorized development cases through the production factory, pinned bundled assets, packaged CLI behavior, website build and rendered layout, and release version consistency. The final model test remains untouched.

The six previously rendered onboarding scenarios used simulated macOS permission APIs. The underlying permission manager and onboarding view are unchanged from that verified fix and are compiled into this candidate. A fresh macOS account permission grant flow remains unverified; real permissions are not reset during release preparation.

The download handlers, local download paths, and release notes are staged for 0.3.0. The public appcast still points to the published 0.2.0 artifact. Do not deploy this website by itself: sign and notarize the candidate, upload the matching app, generate the signed appcast, update production download configuration, and publish the coordinated app and website only after release approval. No upload, push, deploy, install, or running-app replacement is part of this preparation.
