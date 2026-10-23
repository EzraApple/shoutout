# Update download measurements

Measured on October 22, 2026 using the public arm64 0.3.0 (build 21) and 0.3.1 (build 22) DMGs. The application contents were unchanged during compression comparisons.

| Artifact | Bytes | Reduction from full 0.3.1 DMG |
| --- | ---: | ---: |
| Current zlib DMG | 75,203,487 | — |
| LZFSE DMG | 68,810,245 | 8.50% |
| LZMA DMG | 63,727,793 | 15.26% |
| Sparkle delta, 0.3.0 to 0.3.1 | 1,404,470 | 98.13% |

The patch was generated both directly with Sparkle's `BinaryDelta create --version=4` and through the updated `generate-appcast.sh`. Applying the patch reproduced all 573 files, paths, symlinks, and permission modes in the public 0.3.1 app. SHA-256 checks matched every regular file. `codesign --verify --deep --strict` passed on the reconstructed app. The generated feed retained the signed full DMG and included a signed delta from build 21. Its manifest included the full DMG, patch, and authored notes.

The updated pipeline restored the public 0.3.0 baseline from its prior committed appcast, verified its length and EdDSA signature with `sign_update`, and kept it outside the cleared `dist/` directory. A second generation reused the baseline. Staging copied the patch alongside the full DMG and feed into an isolated test public directory.

`hdiutil convert` produced the two compressed DMGs from the same public 0.3.1 image. The LZMA image passed `hdiutil verify`, mounted, and contained a valid signed app. The changed `create-dmg.sh` also produced and verified a headless LZMA DMG from the same signed app. ULMO is supported since macOS 10.15, below ShoutOut's macOS 15 requirement.

The speech model already lives in Application Support and survives replacement of the app. Its current pinned GGUF is 731,357,568 bytes. Mini cleanup is bundled: 44,512,792 bytes of model files plus 232,064 bytes of vocabulary and configuration. Delta updates reuse its unchanged contents while preserving offline cleanup.

These are transfer-size measurements for one real update, not a guarantee for every release or a measure of end-to-end update latency. Model or framework changes can increase patch size. Users without a matching patch, or with a patch failure, still get the full DMG through Sparkle's fallback. The original signed 0.3.0 and 0.3.1 DMGs and the signed delta were subsequently uploaded to R2 without changing their bytes. No installed app was replaced and no new app version was signed or notarized. LZMA compression takes effect on the next app release. Live Sparkle UI installation, slower networks, and the oldest supported macOS were not tested.
