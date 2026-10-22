#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
macos="$root/apps/macos"
base_app="$HOME/Applications/ShoutOut.app"
output="$macos/dist-mini-trial"
bundle_id="com.ezraapple.shoutout.mini-trial"
configuration="${SHOUTOUT_TRIAL_CONFIGURATION:-debug}"

case "$configuration" in
    debug|release) ;;
    *) echo "SHOUTOUT_TRIAL_CONFIGURATION must be debug or release" >&2; exit 2 ;;
esac
plist="$base_app/Contents/Info.plist"
if [[ "$(plutil -extract CFBundleIdentifier raw -o - "$plist")" != com.ezraapple.shoutout || \
      "$(plutil -extract CFBundleShortVersionString raw -o - "$plist")" != 0.3.0 ]]; then
    echo "This local builder requires the installed ShoutOut 0.3.0 runtime." >&2
    exit 1
fi
codesign --verify --deep --strict "$base_app"
python3 "$macos/scripts/mini-assets.py" verify "$base_app/Contents/Resources/MiniCleanup"
test -x "$base_app/Contents/Helpers/HexSpeechWorker"
test -f "$base_app/Contents/Resources/mlx-swift_Cmlx.bundle/default.metallib"

swift build --package-path "$macos" -c "$configuration" --product ShoutOut
bin="$(swift build --package-path "$macos" -c "$configuration" --show-bin-path)"
mkdir -p "$output"
stage="$(mktemp -d "$output/.indicator-stage.XXXXXX")"
app="$stage/ShoutOut Mini Trial.app"

# Reuse the verified release's public runtime, resources, and bundled Mini model.
# No installed executable, preferences, history, or dictionary is changed.
ditto "$base_app" "$app"
cp "$bin/ShoutOut" "$app/Contents/MacOS/ShoutOut"
if ! otool -l "$app/Contents/MacOS/ShoutOut" | grep -F '@executable_path/../Frameworks' >/dev/null; then
    install_name_tool -add_rpath '@executable_path/../Frameworks' "$app/Contents/MacOS/ShoutOut"
fi
plist="$app/Contents/Info.plist"
plutil -replace CFBundleIdentifier -string "$bundle_id" "$plist"
plutil -replace CFBundleName -string "ShoutOut Mini Trial" "$plist"
plutil -replace CFBundleDisplayName -string "ShoutOut Mini Trial" "$plist"
plutil -replace ShoutOutMiniTrial -bool true "$plist"
plutil -replace ShoutOutLocalTrial -bool true "$plist"
plutil -remove SUFeedURL "$plist"
plutil -remove SUPublicEDKey "$plist"
plutil -replace ShoutOutGitCommit -string "$(git -C "$root" rev-parse --short=12 HEAD)" "$plist"
plutil -replace ShoutOutBuiltAt -string "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$plist"

# Keep the existing trial's stable local identity and its separate permissions.
codesign --force --sign - --timestamp=none \
    --entitlements "$macos/Resources/ShoutOut.entitlements" \
    --requirements "=designated => identifier \"$bundle_id\"" "$app"
codesign --verify --deep --strict "$app"

final_app="$output/ShoutOut Mini Trial.app"
if [[ -e "$final_app" ]]; then
    mv "$final_app" "$output/ShoutOut Mini Trial-$(date +%Y%m%d-%H%M%S).app"
fi
mv "$app" "$final_app"
rmdir "$stage"
echo "Built normal-mode indicator trial: $final_app"
