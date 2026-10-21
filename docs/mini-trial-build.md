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
