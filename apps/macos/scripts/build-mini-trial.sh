#!/bin/bash
set -euo pipefail

# Build a local, isolated Mini trial without touching the release builder or app.
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(dirname "$script_dir")"
repo_dir="$(cd "$project_dir/../.." && pwd)"
base_app="$HOME/Applications/ShoutOut.app"
dist_dir="$project_dir/dist-mini-trial"
bundle_id="com.ezraapple.shoutout.mini-trial"
app_name="ShoutOut Mini Trial.app"

if [[ $# -ne 2 || "$1" != "--model-directory" ]]; then
    echo "usage: $0 --model-directory /absolute/path/to/native-mini-2026-10-21" >&2
    exit 2
fi
model_dir="$2"
if [[ "$model_dir" != /* || ! -d "$model_dir/mini-fixed256.mlpackage" \
    || ! -f "$model_dir/vocab.txt" || ! -f "$model_dir/tokenizer-config.json" ]]; then
    echo "Mini model directory must be absolute and contain the frozen model, vocabulary, and tokenizer config." >&2
    exit 1
fi
if [[ "$(shasum -a 256 "$model_dir/vocab.txt" | cut -d ' ' -f 1)" != \
        "07eced375cec144d27c900241f3e339478dec958f92fddbc551f295c992038a3" || \
    "$(shasum -a 256 "$model_dir/tokenizer-config.json" | cut -d ' ' -f 1)" != \
        "7a248d081af1990bbbb20e98f58f07759f13991aec65a97858bdfd593697efc8" ]]; then
    echo "The Mini vocabulary or tokenizer config does not match the frozen trial." >&2
    exit 1
fi
model_digest="$(python3 - "$model_dir/mini-fixed256.mlpackage" <<'PY'
import hashlib
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
digest = hashlib.sha256()
for path in sorted(path for path in root.rglob("*") if path.is_file()):
    digest.update(path.relative_to(root).as_posix().encode())
    with path.open("rb") as model_file:
        for chunk in iter(lambda: model_file.read(1_048_576), b""):
            digest.update(chunk)
print(digest.hexdigest())
PY
)"
if [[ "$model_digest" != "6c62bb511b9f639998907e578b062d1932e6c79ad55dea6c94fa47f79edc93f5" ]]; then
    echo "The Mini model package does not match the frozen trial." >&2
    exit 1
fi

# The helper is copied from the installed 0.2.0 app so the trial keeps its ASR path.
# Read only; never sign, replace, or launch the installed app.
base_plist="$base_app/Contents/Info.plist"
if [[ ! -f "$base_plist" || \
    "$(plutil -extract ShoutOutGitCommit raw -o - "$base_plist" 2>/dev/null || true)" != "f54f08958b03" || \
    "$(plutil -extract CFBundleIdentifier raw -o - "$base_plist" 2>/dev/null || true)" != "com.ezraapple.shoutout" || \
    ! -x "$base_app/Contents/Helpers/HexSpeechWorker" || \
    ! -d "$base_app/Contents/Resources/HexSpeechWorker/Licenses" ]]; then
    echo "Expected the installed ShoutOut 0.2.0 app at $base_app (commit f54f08958b03) with its speech helper." >&2
    exit 1
fi

if [[ -L "$dist_dir" || -L "$dist_dir/$app_name" ]]; then
    echo "Refusing a symlink in the Mini trial output path." >&2
    exit 1
fi
mkdir -p "$dist_dir"
stage_dir="$(mktemp -d "$dist_dir/.staging.XXXXXX")"
trap 'rm -rf "$stage_dir"' EXIT
app="$stage_dir/$app_name"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" \
    "$app/Contents/Frameworks" "$app/Contents/Helpers"

cd "$project_dir"
swift build -c release --product ShoutOut
bin_dir="$(swift build -c release --product ShoutOut --show-bin-path)"
test -x "$bin_dir/ShoutOut"
cp "$bin_dir/ShoutOut" "$app/Contents/MacOS/ShoutOut"

# SwiftPM resources and dynamic frameworks must sit beside the executable.
for bundle in "$bin_dir"/*.bundle; do
    if [[ -d "$bundle" ]]; then
        cp -R "$bundle" "$app/Contents/Resources/"
    fi
done
for framework in "$bin_dir"/*.framework; do
    if [[ -d "$framework" ]]; then
        cp -R "$framework" "$app/Contents/Frameworks/"
    fi
done
for resource in AppIcon.icns CrabSprites CrabSpritesWall CrabSpriteVariants CrabSpriteWallVariants AppIconVariants; do
    if [[ -e "Resources/$resource" ]]; then
        cp -R "Resources/$resource" "$app/Contents/Resources/"
    fi
done

# Match the 0.2.0 ASR worker and notices. Its binary has only system libraries.
cp "$base_app/Contents/Helpers/HexSpeechWorker" "$app/Contents/Helpers/"
cp -R "$base_app/Contents/Resources/HexSpeechWorker" "$app/Contents/Resources/"

# Preserve the MLX runtime resource used by the app's existing language path.
mlx_bundle="$app/Contents/Resources/mlx-swift_Cmlx.bundle"
if [[ ! -d "$mlx_bundle" || ! -f "$base_app/Contents/Resources/mlx-swift_Cmlx.bundle/default.metallib" ]]; then
    echo "The MLX resource bundle or installed Metal library is missing." >&2
    exit 1
fi
cp "$base_app/Contents/Resources/mlx-swift_Cmlx.bundle/default.metallib" "$mlx_bundle/"

# Copy only the three frozen Mini assets; the source directory also has private replays.
mini_resources="$app/Contents/Resources/MiniCleanup"
mkdir -p "$mini_resources"
cp -R "$model_dir/mini-fixed256.mlpackage" "$mini_resources/"
cp "$model_dir/vocab.txt" "$model_dir/tokenizer-config.json" "$mini_resources/"
cmp "$model_dir/vocab.txt" "$mini_resources/vocab.txt"
cmp "$model_dir/tokenizer-config.json" "$mini_resources/tokenizer-config.json"
diff -qr "$model_dir/mini-fixed256.mlpackage" "$mini_resources/mini-fixed256.mlpackage" >/dev/null

cp Resources/Info.plist "$app/Contents/Info.plist"
plist="$app/Contents/Info.plist"
plutil -replace CFBundleIdentifier -string "$bundle_id" "$plist"
plutil -replace CFBundleName -string "ShoutOut Mini Trial" "$plist"
plutil -replace CFBundleDisplayName -string "ShoutOut Mini Trial" "$plist"
plutil -insert ShoutOutMiniTrial -bool true "$plist"
plutil -insert ShoutOutLocalTrial -bool true "$plist"
plutil -remove SUFeedURL "$plist"
plutil -remove SUPublicEDKey "$plist"
git_commit="$(git -C "$repo_dir" rev-parse --short=12 HEAD)"
if [[ -n "$(git -C "$repo_dir" status --porcelain)" ]]; then
    git_commit="$git_commit-dirty"
fi
plutil -replace ShoutOutGitCommit -string "$git_commit" "$plist"
plutil -replace ShoutOutBuiltAt -string "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$plist"

if [[ -d "$app/Contents/Frameworks/Sparkle.framework" ]] && \
    ! otool -l "$app/Contents/MacOS/ShoutOut" | grep -F '@executable_path/../Frameworks' >/dev/null; then
    install_name_tool -add_rpath '@executable_path/../Frameworks' "$app/Contents/MacOS/ShoutOut"
fi

sign_local() {
    codesign --force --sign - --timestamp=none \
        --preserve-metadata=identifier,entitlements,flags "$1"
}
sign_local "$app/Contents/Helpers/HexSpeechWorker"
for bundle in "$app/Contents/Resources"/*.bundle; do
    if [[ -d "$bundle" ]]; then
        # SwiftPM resource-only bundles can lack code for codesign to sign.
        if ! sign_local "$bundle"; then
            echo "Skipping unsigned resource-only bundle: $bundle" >&2
        fi
    fi
done
for framework in "$app/Contents/Frameworks"/*.framework; do
    [[ -d "$framework" ]] || continue
    current="$framework/Versions/Current"
    for nested in "$current/XPCServices"/*.xpc "$current/Updater.app" "$current/Autoupdate"; do
        if [[ -e "$nested" ]]; then
            sign_local "$nested"
        fi
    done
    sign_local "$framework"
done
codesign --force --sign - --timestamp=none \
    --entitlements Resources/ShoutOut.entitlements \
    --requirements "=designated => identifier \"$bundle_id\"" \
    "$app"
codesign --verify --deep --strict "$app"

final_app="$dist_dir/$app_name"
if [[ -e "$final_app" ]]; then
    # Replace only the previous trial output after a complete and verified build.
    rm -rf "$final_app"
fi
mv "$app" "$final_app"
echo "Built local Mini trial: $final_app"
