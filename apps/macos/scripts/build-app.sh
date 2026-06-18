#!/bin/bash
set -e

# Load .env (check repo root first, then the macOS app)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ROOT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
for ENV_FILE in "$ROOT_DIR/.env" "$PROJECT_DIR/.env"; do
    if [ -f "$ENV_FILE" ]; then
        set -a
        source "$ENV_FILE"
        set +a
        break
    fi
done

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

APP_NAME="ShoutOut"
EXECUTABLE_NAME="ShoutOut"
BUNDLE_ID="com.ezraapple.shoutout"
DIST_DIR="dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
UNIVERSAL="${UNIVERSAL:-true}"
NOTARY_PROFILE="${NOTARY_PROFILE:-notarytool-profile}"

build_mlx_metal_runtime() {
    local source_dir=".build/checkouts/mlx-swift/Source/Cmlx/mlx-generated/metal"
    if [ ! -d "$source_dir" ]; then
        return
    fi

    if ! xcrun --sdk macosx --find metal >/dev/null 2>&1 \
        || ! xcrun --sdk macosx --find metallib >/dev/null 2>&1; then
        echo -e "${RED}Error: MLX language cleanup needs Apple's Metal Toolchain.${NC}"
        echo -e "${YELLOW}Install it with: xcodebuild -downloadComponent MetalToolchain${NC}"
        exit 1
    fi

    local temp_dir="$DIST_DIR/mlx-metal-build"
    local output_bundle="$APP_BUNDLE/Contents/Resources/mlx-swift_Cmlx.bundle"
    rm -rf "$temp_dir"
    mkdir -p "$temp_dir" "$output_bundle"

    local has_sources=false
    for metal_source in "$source_dir"/*.metal; do
        if [ ! -f "$metal_source" ]; then
            continue
        fi
        has_sources=true
        local kernel_name
        kernel_name="$(basename "$metal_source" .metal)"
        xcrun -sdk macosx metal \
            -x metal \
            -Wall \
            -Wextra \
            -fno-fast-math \
            -Wno-c++17-extensions \
            -Wno-c++20-extensions \
            -mmacosx-version-min=14.0 \
            -c "$metal_source" \
            -I"$source_dir" \
            -o "$temp_dir/$kernel_name.air"
    done

    if [ "$has_sources" = false ]; then
        echo -e "${YELLOW}Warning: MLX Metal source directory had no .metal files.${NC}"
        return
    fi

    xcrun -sdk macosx metallib "$temp_dir"/*.air -o "$output_bundle/default.metallib"
    echo -e "${BLUE}Built MLX Metal runtime: $output_bundle/default.metallib${NC}"
}

select_speech_analyzer_toolchain_if_available() {
    if [ -n "${DEVELOPER_DIR:-}" ]; then
        return
    fi

    if swift --version 2>/dev/null | grep -Eq 'Apple Swift version (6\.[2-9]|[7-9])'; then
        return
    fi

    local clt_dir="/Library/Developer/CommandLineTools"
    if [ -x "$clt_dir/usr/bin/swift" ] \
        && DEVELOPER_DIR="$clt_dir" swift --version 2>/dev/null \
            | grep -Eq 'Apple Swift version (6\.[2-9]|[7-9])'; then
        export DEVELOPER_DIR="$clt_dir"
        echo -e "${BLUE}Using current Command Line Tools for Apple Dictation support.${NC}"
    fi
}

echo -e "${BLUE}Building $APP_NAME...${NC}"
select_speech_analyzer_toolchain_if_available

# Clean previous builds
echo -e "${BLUE}Cleaning previous builds...${NC}"
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

cd "$PROJECT_DIR"

# Build release binary
if [ "$UNIVERSAL" = "true" ]; then
    echo -e "${BLUE}Building release binary (universal)...${NC}"
    swift build -c release --product "$EXECUTABLE_NAME" --arch arm64 --arch x86_64
    BUILD_DIR=".build/apple/Products/Release"
else
    echo -e "${BLUE}Building release binary (host arch only)...${NC}"
    swift build -c release --product "$EXECUTABLE_NAME"
    BUILD_DIR="$(swift build -c release --product "$EXECUTABLE_NAME" --show-bin-path)"
fi

# Verify binary was created
if [ ! -f "$BUILD_DIR/$EXECUTABLE_NAME" ]; then
    echo -e "${RED}Error: Binary not found at $BUILD_DIR/$EXECUTABLE_NAME${NC}"
    exit 1
fi

# Create app bundle structure
echo -e "${BLUE}Creating app bundle structure...${NC}"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
mkdir -p "$APP_BUNDLE/Contents/Frameworks"

# Copy binary
cp "$BUILD_DIR/$EXECUTABLE_NAME" "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE_NAME"

# Copy Info.plist
cp "Resources/Info.plist" "$APP_BUNDLE/Contents/"

# Stamp the bundle with traceable build metadata. Release scripts may override
# SHOUTOUT_VERSION / SHOUTOUT_BUILD from the environment.
INFO_PLIST="$APP_BUNDLE/Contents/Info.plist"
BUILD_VERSION="${SHOUTOUT_VERSION:-$(plutil -extract CFBundleShortVersionString raw -o - "$INFO_PLIST" 2>/dev/null || echo "0.0.0")}"
BUILD_NUMBER="${SHOUTOUT_BUILD:-$(plutil -extract CFBundleVersion raw -o - "$INFO_PLIST" 2>/dev/null || echo "0")}"
GIT_COMMIT="$(git -C "$ROOT_DIR" rev-parse --short=12 HEAD 2>/dev/null || echo "unknown")"
BUILT_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
plutil -replace CFBundleShortVersionString -string "$BUILD_VERSION" "$INFO_PLIST"
plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$INFO_PLIST"
plutil -replace ShoutOutGitCommit -string "$GIT_COMMIT" "$INFO_PLIST"
plutil -replace ShoutOutBuiltAt -string "$BUILT_AT" "$INFO_PLIST"
echo -e "${BLUE}Stamped bundle version: $BUILD_VERSION ($BUILD_NUMBER), git $GIT_COMMIT, built $BUILT_AT${NC}"

SPARKLE_FEED_URL="${SPARKLE_FEED_URL:-https://shoutout.sh/appcast.xml}"
plutil -replace SUFeedURL -string "$SPARKLE_FEED_URL" "$INFO_PLIST"
if [[ -n "${SPARKLE_PUBLIC_ED_KEY:-}" && "${SPARKLE_PUBLIC_ED_KEY:-}" != "paste SUPublicEDKey here" ]]; then
    plutil -replace SUPublicEDKey -string "$SPARKLE_PUBLIC_ED_KEY" "$INFO_PLIST"
    echo -e "${BLUE}Sparkle updates configured for: $SPARKLE_FEED_URL${NC}"
else
    echo -e "${YELLOW}Sparkle public key not set; updater will stay disabled in this build.${NC}"
fi

# Copy resource bundles if they exist (contains bundled resources)
for RESOURCE_BUNDLE in "$BUILD_DIR"/*.bundle; do
    if [ -d "$RESOURCE_BUNDLE" ]; then
        echo -e "${BLUE}Copying resource bundle: $(basename "$RESOURCE_BUNDLE")${NC}"
        cp -R "$RESOURCE_BUNDLE" "$APP_BUNDLE/Contents/Resources/"
    fi
done

build_mlx_metal_runtime

# Copy icon if it exists
if [ -f "Resources/AppIcon.icns" ]; then
    echo -e "${BLUE}Copying app icon...${NC}"
    cp "Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/"
else
    echo -e "${YELLOW}Warning: AppIcon.icns not found. Using default icon.${NC}"
fi

if [ -d "Resources/CrabSprites" ]; then
    echo -e "${BLUE}Copying crab sprite frames...${NC}"
    cp -R "Resources/CrabSprites" "$APP_BUNDLE/Contents/Resources/"
fi

if [ -d "Resources/CrabSpritesWall" ]; then
    echo -e "${BLUE}Copying wall crab sprite frames...${NC}"
    cp -R "Resources/CrabSpritesWall" "$APP_BUNDLE/Contents/Resources/"
fi

if [ -d "Resources/CrabSpriteVariants" ]; then
    echo -e "${BLUE}Copying tinted crab sprite frames...${NC}"
    cp -R "Resources/CrabSpriteVariants" "$APP_BUNDLE/Contents/Resources/"
fi

if [ -d "Resources/CrabSpriteWallVariants" ]; then
    echo -e "${BLUE}Copying tinted wall crab sprite frames...${NC}"
    cp -R "Resources/CrabSpriteWallVariants" "$APP_BUNDLE/Contents/Resources/"
fi

if [ -d "Resources/AppIconVariants" ]; then
    echo -e "${BLUE}Copying app icon variants...${NC}"
    cp -R "Resources/AppIconVariants" "$APP_BUNDLE/Contents/Resources/"
fi

# Copy dynamic frameworks linked by SwiftPM, including Sparkle.
for FRAMEWORK in "$BUILD_DIR"/*.framework; do
    if [ -d "$FRAMEWORK" ]; then
        echo -e "${BLUE}Copying framework: $(basename "$FRAMEWORK")${NC}"
        rm -rf "$APP_BUNDLE/Contents/Frameworks/$(basename "$FRAMEWORK")"
        cp -R "$FRAMEWORK" "$APP_BUNDLE/Contents/Frameworks/"
    fi
done

# Set executable permissions
chmod +x "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE_NAME"

if [ -d "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework" ]; then
    if ! otool -l "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE_NAME" \
        | grep -q '@executable_path/../Frameworks'; then
        echo -e "${BLUE}Adding app framework rpath...${NC}"
        install_name_tool -add_rpath "@executable_path/../Frameworks" \
            "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE_NAME"
    fi
fi

echo -e "${GREEN}App bundle created at: $APP_BUNDLE${NC}"

# Show binary info
echo -e "${BLUE}Binary info:${NC}"
file "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE_NAME"
lipo -info "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE_NAME"

sign_developer_id() {
    local path="$1"
    codesign --force --sign "$CODE_SIGN_IDENTITY" \
        --options runtime \
        --timestamp \
        --preserve-metadata=identifier,entitlements,flags \
        "$path"
}

sign_adhoc() {
    local path="$1"
    codesign --force --sign - \
        --preserve-metadata=identifier,entitlements,flags \
        "$path"
}

sign_framework_inside_out() {
    local framework_path="$1"
    local signer="$2"
    local framework_current="$framework_path/Versions/Current"

    for nested_path in \
        "$framework_current/XPCServices"/*.xpc \
        "$framework_current/Updater.app" \
        "$framework_current/Autoupdate"; do
        if [ -e "$nested_path" ]; then
            echo -e "${BLUE}Signing nested Sparkle code: $(basename "$nested_path")${NC}"
            "$signer" "$nested_path"
        fi
    done

    echo -e "${BLUE}Signing framework: $(basename "$framework_path")${NC}"
    "$signer" "$framework_path"
}

# Code signing
if [[ -n "${CODE_SIGN_IDENTITY:-}" ]]; then
    echo -e "${BLUE}Code signing with identity: $CODE_SIGN_IDENTITY${NC}"

    # Sign inside-out: nested bundles first, then the main app
    for RESOURCE_BUNDLE_PATH in "$APP_BUNDLE/Contents/Resources"/*.bundle; do
        if [ ! -d "$RESOURCE_BUNDLE_PATH" ]; then
            continue
        fi
        echo -e "${BLUE}Signing nested resource bundle: $(basename "$RESOURCE_BUNDLE_PATH")${NC}"
        if ! sign_developer_id "$RESOURCE_BUNDLE_PATH"; then
            echo -e "${YELLOW}Skipping unsigned resource-only bundle: $(basename "$RESOURCE_BUNDLE_PATH")${NC}"
        fi
    done

    for FRAMEWORK_PATH in "$APP_BUNDLE/Contents/Frameworks"/*.framework; do
        if [ ! -d "$FRAMEWORK_PATH" ]; then
            continue
        fi
        sign_framework_inside_out "$FRAMEWORK_PATH" sign_developer_id
    done

    echo -e "${BLUE}Signing main app bundle...${NC}"
    codesign --force --sign "$CODE_SIGN_IDENTITY" \
        --entitlements "Resources/ShoutOut.entitlements" \
        --options runtime \
        --timestamp \
        "$APP_BUNDLE"

    echo -e "${GREEN}Code signing complete!${NC}"

    # Verify code signature
    echo -e "${BLUE}Verifying code signature...${NC}"
    codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

    # Notarize the app
    if [ "${SKIP_NOTARIZE:-false}" != "true" ]; then
        echo -e "${BLUE}Submitting for notarization...${NC}"
        NOTARIZE_ZIP="$DIST_DIR/ShoutOut.zip"
        ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$NOTARIZE_ZIP"

        NOTARIZE_OUTPUT=$(xcrun notarytool submit "$NOTARIZE_ZIP" \
            --keychain-profile "$NOTARY_PROFILE" \
            --wait --timeout 30m 2>&1) || true

        echo "$NOTARIZE_OUTPUT"

        SUBMISSION_ID=$(echo "$NOTARIZE_OUTPUT" | grep "  id:" | head -1 | awk '{print $2}')

        if echo "$NOTARIZE_OUTPUT" | grep -q "status: Accepted"; then
            rm -f "$NOTARIZE_ZIP"

            echo -e "${BLUE}Stapling notarization ticket...${NC}"
            xcrun stapler staple "$APP_BUNDLE"
            echo -e "${GREEN}Notarization complete!${NC}"
        else
            rm -f "$NOTARIZE_ZIP"

            if [ -n "$SUBMISSION_ID" ]; then
                echo -e "${YELLOW}Fetching notarization log...${NC}"
                xcrun notarytool log "$SUBMISSION_ID" --keychain-profile "$NOTARY_PROFILE" 2>&1 || true
            fi

            echo -e "${RED}Notarization failed or timed out.${NC}"
            exit 1
        fi
    fi
else
    # Ad-hoc sign for local use
    echo -e "${YELLOW}No CODE_SIGN_IDENTITY set. Ad-hoc signing for local use...${NC}"

    for RESOURCE_BUNDLE_PATH in "$APP_BUNDLE/Contents/Resources"/*.bundle; do
        if [ ! -d "$RESOURCE_BUNDLE_PATH" ]; then
            continue
        fi
        echo -e "${BLUE}Ad-hoc signing nested resource bundle: $(basename "$RESOURCE_BUNDLE_PATH")${NC}"
        if ! sign_adhoc "$RESOURCE_BUNDLE_PATH"; then
            echo -e "${YELLOW}Skipping unsigned resource-only bundle: $(basename "$RESOURCE_BUNDLE_PATH")${NC}"
        fi
    done

    for FRAMEWORK_PATH in "$APP_BUNDLE/Contents/Frameworks"/*.framework; do
        if [ ! -d "$FRAMEWORK_PATH" ]; then
            continue
        fi
        sign_framework_inside_out "$FRAMEWORK_PATH" sign_adhoc
    done

    codesign --force --sign - \
        --entitlements "Resources/ShoutOut.entitlements" \
        --requirements "=designated => identifier \"$BUNDLE_ID\"" \
        "$APP_BUNDLE"
    echo -e "${GREEN}Ad-hoc signing complete!${NC}"
    echo -e "${YELLOW}Note: Users will see a Gatekeeper warning on first launch.${NC}"
fi

echo -e "${GREEN}Build complete!${NC}"
