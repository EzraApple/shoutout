# DMG Readiness Checklist

Use this before publishing a public ShoutOut DMG.

## Account And Certificates

- Apple Developer Program membership is active.
- Developer ID Application certificate is installed in Keychain.
- `CODE_SIGN_IDENTITY` is set to the Developer ID Application identity.
- `NOTARY_PROFILE` points at a stored `xcrun notarytool` keychain profile.

## Build

```bash
make test
UNIVERSAL=true CODE_SIGN_IDENTITY="Developer ID Application: ..." make release-dmg
```

Expected output:

- `apps/macos/dist/ShoutOut.app`
- `apps/macos/dist/ShoutOut-<version>.dmg`
- app signature verifies
- DMG signature verifies
- app and DMG notarization succeed when `SKIP_NOTARIZE` is not set

For a local unsigned packaging dry-run before certificates are ready:

```bash
SKIP_NOTARIZE=true make release-dmg
```

## Fresh Install QA

- Mount the DMG.
- Drag ShoutOut into `/Applications`.
- Launch from `/Applications`.
- Complete onboarding.
- Grant Microphone, Speech Recognition, Accessibility, and Input Monitoring.
- Confirm Fn hold-to-record works.
- Confirm text insertion works in Notes, TextEdit, Safari, Chrome, Slack, Cursor, and VS Code.
- Confirm a denied permission leaves a clear recovery path.
- Confirm Settings shows model readiness and download progress.

## Upload

- Do not publish the current dry-run DMG. Finish the LM pass work first, then cut the real release.
- Confirm the website project has these Vercel env vars set in Production and Preview:
  - `VITE_POSTHOG_KEY`
  - `VITE_POSTHOG_HOST`
  - `POSTHOG_PROJECT_API_KEY`
  - `POSTHOG_HOST`
  - `SHOUTOUT_RELEASE_VERSION`
  - `SHOUTOUT_DMG_URL`
- Store notarization credentials once on the release machine:

```bash
make notary-credentials
```

- Build and notarize the real universal DMG:

```bash
make release-preflight
UNIVERSAL=true make release-dmg
```

- Generate the Sparkle appcast and stage the DMG, release notes, and appcast into the website:

```bash
make sparkle-appcast
npm --prefix apps/web run build
```

- Upload the DMG and release notes to the linked Vercel Blob store:

```bash
make blob-upload-dmg
```

- Copy the printed DMG Blob URL into `SHOUTOUT_DMG_URL` for Production and Preview. The `/download` route tracks `download started` in PostHog and redirects to `SHOUTOUT_DMG_URL` when set, otherwise it falls back to `/releases/ShoutOut-<version>.dmg`.
- If Sparkle should download from Blob too, set `SPARKLE_DOWNLOAD_URL_PREFIX` to the Blob `releases/` URL before running `make sparkle-appcast`. Unless `SPARKLE_RELEASE_NOTES_URL_PREFIX` is set separately, the release notes link will use the same Blob prefix.
- Verify these public paths after deploy:
  - `https://shoutout.sh/appcast.xml`
  - Blob URL from `SHOUTOUT_DMG_URL`
  - `https://shoutout.sh/releases/ShoutOut-<version>.md`
- Verify PostHog receives `download clicked` and `download started`.
- Verify the public download URL from a clean browser session.
- Verify Sparkle update checking from an older installed build before announcing broadly.
