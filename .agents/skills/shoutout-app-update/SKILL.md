---
name: shoutout-app-update
description: Use when publishing a ShoutOut macOS app update, bumping Info.plist/appcast/download versions, building a signed DMG, uploading release artifacts, writing release notes, or pushing release commits to main.
---

# ShoutOut App Update

Treat an app update as a shipped Sparkle boundary, not just a code push. The update is only complete when version metadata, release notes, DMG, R2 upload, appcast, validation, commit, and push all agree.

## Release Notes

Write concise, mildly user-facing bullets. They should describe the user-visible behavior that changed in the shipped app, not the development path, implementation constraint, or behavior that merely did not regress.

Good for a hands-free recording fix:

- Fixes Fn/Globe double-tap so hands-free recordings reliably continue after the second tap.
- Prevents quick double-taps from turning into two short recordings.
- Shows the hands-free recording state immediately after the second tap.

Avoid:

- Generic notes like "Bug fixes and improvements."
- Deep internals like enum names, timer phases, callback signatures, or test names.
- Non-regression notes like "keeps hold-to-record fast" unless the user was already experiencing that as a shipped bug.
- Development-history notes like "preserves the buffer" when the user-facing result is "does not drop the beginning of the recording."
- Claims not backed by the shipped patch and validation.

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
SHOUTOUT_DMG_HEADLESS=true UNIVERSAL=false make release-dmg
make r2-upload-release
npm --prefix apps/web run build
```

Notes:

- Use the repo's current architecture policy. The public appcast has been arm64; do not switch to universal unless the release plan says so.
- `make r2-upload-release` generates the signed appcast and delta patches, uploads the notarized DMG, release notes, and referenced patches to the `shoutout-releases` R2 bucket with Wrangler, verifies their public lengths at `downloads.shoutout.sh`, then stages `apps/web/public/appcast.xml`.
- Archive history lives in `apps/macos/.release-archives/sparkle/`, outside the cleared build output. Fresh checkouts restore and verify recent signed baseline DMGs from the committed feed. Keep older generated feed items so later releases can restore their baselines.
- `make sparkle-appcast` is for manual hosting. Upload every file listed in `apps/macos/dist/sparkle-release.json` before publishing its staged feed. Do not run it separately before the R2 upload workflow. The manifest records the bucket and public URL prefix from release settings.
- Keep generated DMG files out of git; `apps/web/public/releases/*.dmg` and `apps/macos/dist/` are ignored.

## Production Download Env

The `/download` API can override committed defaults with production env vars. After the R2 upload, update any such overrides before the production deploy:

```bash
npx vercel env update SHOUTOUT_RELEASE_VERSION --environment production --value '<version>' --yes
npx vercel env update SHOUTOUT_DMG_URL --environment production --value 'https://downloads.shoutout.sh/releases/ShoutOut-<version>.dmg' --yes
```

Then deploy or wait for the Git-backed production deployment, and verify:

```bash
curl -fsSL 'https://shoutout.sh/download?source=verify' -o /tmp/shoutout.dmg -w '%{url_effective}\n'
rm -f /tmp/shoutout.dmg
```

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

Confirm `apps/web/public/appcast.xml` points at the uploaded R2 URLs, includes the new Sparkle version/build, and has a non-empty `sparkle:edSignature`.
Confirm each `sparkle:deltas` enclosure has a signed, downloadable patch with the advertised length. Leave the full DMG enclosure in place for first installs and fallback updates. Do not commit generated DMGs or patches.

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
