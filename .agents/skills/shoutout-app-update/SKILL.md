---
name: shoutout-app-update
description: Use when publishing a ShoutOut macOS app update, bumping Info.plist/appcast/download versions, building a signed DMG, uploading release artifacts, writing release notes, or pushing release commits to main.
---

# ShoutOut App Update

Treat an app update as a shipped Sparkle boundary, not just a code push. The update is only complete when version metadata, release notes, DMG, blob upload, appcast, validation, commit, and push all agree.

## Release Notes

Write concise, mildly user-facing bullets. They should name the actual fixed behavior without dumping implementation details.

Good:

- Fixes hands-free recording so a quick Fn/Globe double-tap keeps the first bit of audio instead of acting like two tiny recordings.
- Keeps hold-to-record fast; the quick hold activation timing is unchanged.
- Switches the recording overlay into hands-free mode as soon as the second tap lands.

Avoid:

- Generic notes like "Bug fixes and improvements."
- Deep internals like enum names, timer phases, callback signatures, or test names.
- Claims not backed by the patch and validation.

## Version Bump

Before building, check the shipped boundary:

```bash
plutil -extract CFBundleShortVersionString raw -o - apps/macos/Resources/Info.plist
plutil -extract CFBundleVersion raw -o - apps/macos/Resources/Info.plist
sed -n '1,80p' apps/web/public/appcast.xml
```

For a new update, bump all public version pointers together:

- `apps/macos/Resources/Info.plist`: `CFBundleShortVersionString` and `CFBundleVersion`.
- `api/download.js`: `DEFAULT_RELEASE_VERSION`.
- `apps/web/api/download.js`: `DEFAULT_RELEASE_VERSION`.
- `apps/web/index.html`: `data-local-download-href` and `data-track-release-version`.
- `apps/web/public/releases/ShoutOut-<version>.md`: release notes.

Do not overwrite the current shipped version unless explicitly doing a same-version artifact replacement and the user understands the risk.

## Build And Publish

Run the release path from the repo root:

```bash
make release-preflight
./scripts/test.sh
npm --prefix apps/web run build
UNIVERSAL=false make release-dmg
mkdir -p apps/macos/dist/sparkle
cp apps/web/public/releases/ShoutOut-<version>.md apps/macos/dist/sparkle/ShoutOut-<version>.md
make blob-upload-dmg
make sparkle-appcast
npm --prefix apps/web run build
```

Notes:

- Use the repo's current architecture policy. The public appcast has been arm64; do not switch to universal unless the release plan says so.
- `make blob-upload-dmg` uploads the notarized DMG and release notes to Vercel Blob.
- `make sparkle-appcast` signs the appcast and stages `apps/web/public/appcast.xml`.
- Keep generated DMG files out of git; `apps/web/public/releases/*.dmg` and `apps/macos/dist/` are ignored.

## Validate Before Push

Check the staged release metadata:

```bash
rg -n "<version>|ShoutOut-<version>" \
  apps/macos/Resources/Info.plist \
  api/download.js \
  apps/web/api/download.js \
  apps/web/index.html \
  apps/web/public/appcast.xml \
  apps/web/public/releases/ShoutOut-<version>.md
git diff --check
git status --short
```

Confirm `apps/web/public/appcast.xml` points at the uploaded Blob URLs, includes the new Sparkle version/build, and has a non-empty `sparkle:edSignature`.

## Push

If the Codex worktree is detached but `HEAD` matches `origin/main`, commit locally and push directly:

```bash
git fetch origin main
git rev-list --left-right --count HEAD...origin/main
git add <release files>
git commit -m "Release ShoutOut <version>"
git push origin HEAD:main
```

If `HEAD` diverges from `origin/main`, resolve that deliberately before pushing. Do not publish an app update from a stale release line.
