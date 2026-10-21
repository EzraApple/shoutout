# Local Mini trial app

The Mini trial uses a separate app identity: `ShoutOut Mini Trial.app` with bundle ID `com.ezraapple.shoutout.mini-trial`. It has its own settings, permissions, and model cache. The installed `~/Applications/ShoutOut.app` is read only and stays in place.

Build from this checkout after the Mini app startup configuration is present:

```sh
apps/macos/scripts/build-mini-trial.sh --model-directory \
  /Users/ezraapple/Projects/dictation-cleanup/.private/native-mini-2026-10-21
```

The script builds the current `ShoutOut` Swift executable and writes `apps/macos/dist-mini-trial/ShoutOut Mini Trial.app`. It copies the 0.2.0 ASR worker from the installed app only after verifying the app's recorded commit, `f54f08958b03`. It also includes SwiftPM resource bundles, Sparkle's framework, icons and sprites, the installed MLX Metal runtime, and only these Mini files in `Contents/Resources/MiniCleanup`: `mini-fixed256.mlpackage`, `vocab.txt`, and `tokenizer-config.json`. The source folder contains private replay data that must stay outside the app and Git.

The trial plist sets `ShoutOutMiniTrial` and `ShoutOutLocalTrial` to true, sets the trial bundle ID and name, and removes the Sparkle feed and public key. The script signs the bundle ad hoc for local use and checks its signature. It does not read `.env`, notarize, publish, create a DMG, install, or launch the app. It replaces only a prior `apps/macos/dist-mini-trial/ShoutOut Mini Trial.app` after the new bundle passes signing checks.

Inspect the package before launching it:

```sh
trial='apps/macos/dist-mini-trial/ShoutOut Mini Trial.app'
plutil -p "$trial/Contents/Info.plist"
codesign --verify --deep --strict "$trial"
find "$trial/Contents/Resources/MiniCleanup" -type f
```

The model source and output paths are local to this Mac. If the installed base app changes, inspect the new helper and update the checked commit before rebuilding. A successful build and signature check do not confirm the Mini startup path or live dictation behavior; verify those in the trial app before using it for comparisons.

## Coordinated Mini release

The current trial has a single Text cleanup toggle and no tone chooser. The website source on this branch describes that behavior. It is not deployed. Historical release notes retain the behavior of their dated versions.

The same release candidate includes the Input Monitoring onboarding fix from `839e22e`. After Accessibility is granted, setup resolves Input Monitoring access and skips its page when access is already available. If access is still missing, the page remains without automatically opening System Settings. Resuming setup and granting access later also advance correctly. This change is already in the branch; do not apply it again.

The onboarding release build and six rendered flows with simulated macOS permission APIs passed. Evidence is in the private `.local-evals/input-monitoring/verification.json` and `build.log`. A fresh macOS permission reset and grant flow remains unverified. The installed trial was not replaced or restarted for this fix.

Before the public update:

1. Bundle and activate Mini in the normal release build. The current release builder and production default still use Llama; a successful trial build does not change them.
2. Migrate existing cleanup-model and tone preferences to the single light-cleanup path. Preserve the user's cleanup on/off choice, dictionary, shortcut, and history. Old tone values must not trigger a tone rewrite, capitalization pass, or Llama download in the Mini release.
3. Check the upgraded app's settings, dictionary preview, history labels, startup, and paste behavior with old Normal, Casual, Formal, and cleanup-off preferences. Retain old model attribution in historical entries; do not reinterpret old results as Mini results.
   Include the onboarding fix in these checks: fresh Accessibility grant, denied Input Monitoring, a later grant, existing access, skipped Accessibility, and resumed setup. Keep simulated-flow evidence separate from a fresh macOS permission grant test.
4. Publish the matching app, download metadata, and website copy together. Do not deploy the new website while its download still delivers the tone-rewrite app.

Keep experimental formatting or a future tone layer separate from this update. No such controls or features are promised in the prepared website copy.
