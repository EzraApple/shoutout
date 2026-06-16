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

- Upload the stapled DMG.
- Update the website download link.
- Verify the public download URL from a clean browser session.
