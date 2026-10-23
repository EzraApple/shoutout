#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
macos="$root/apps/macos"
bundle="$macos/dist/Indicator Preview.app"

swift build --package-path "$macos" --product ShoutOut
bin="$(swift build --package-path "$macos" --show-bin-path)"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources" "$bundle/Contents/Frameworks"
cp "$bin/ShoutOut" "$bundle/Contents/MacOS/ShoutOut"
if [[ -f "$bin/mlx.metallib" ]]; then
    cp "$bin/mlx.metallib" "$bundle/Contents/MacOS/mlx.metallib"
fi
cp "$macos/Resources/Info.plist" "$bundle/Contents/Info.plist"
plutil -replace CFBundleIdentifier -string com.ezraapple.shoutout.indicator-preview "$bundle/Contents/Info.plist"
plutil -replace CFBundleName -string "Indicator Preview" "$bundle/Contents/Info.plist"
plutil -replace CFBundleDisplayName -string "Indicator Preview" "$bundle/Contents/Info.plist"
plutil -replace ShoutOutLocalTrial -bool true "$bundle/Contents/Info.plist"
for resource in CrabSpritesWall CrabSpriteWallVariants AppIcon.icns; do
    if [[ -e "$macos/Resources/$resource" ]]; then
        cp -R "$macos/Resources/$resource" "$bundle/Contents/Resources/"
    fi
done
ditto "$bin/Sparkle.framework" "$bundle/Contents/Frameworks/Sparkle.framework"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$bundle/Contents/MacOS/ShoutOut"
codesign --force --deep --sign - "$bundle"
mkdir -p "$root/.local-evals/indicator-anchors"
/usr/bin/open -n --env SHOUTOUT_CLASSIC_PREVIEW=1 --env SHOUTOUT_SKIP_USER_INSTALL_RELOCATION=1 \
    --env "SHOUTOUT_INDICATOR_DEBUG_PATH=$root/.local-evals/indicator-anchors/placement.json" "$bundle"
