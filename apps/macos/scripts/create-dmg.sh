#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ROOT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# Load .env (check repo root first, then the macOS app)
for ENV_FILE in "$ROOT_DIR/.env" "$PROJECT_DIR/.env"; do
    if [ -f "$ENV_FILE" ]; then
        set -a
        source "$ENV_FILE"
        set +a
        break
    fi
done

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'
YELLOW='\033[0;33m'
NOTARY_PROFILE="${NOTARY_PROFILE:-notarytool-profile}"

# Read version from Info.plist
VERSION=$(plutil -extract CFBundleShortVersionString raw -o - "$PROJECT_DIR/Resources/Info.plist" 2>/dev/null || true)

if [ -z "$VERSION" ]; then
    echo -e "${RED}Error: Could not read version from Info.plist${NC}"
    exit 1
fi

APP_NAME="ShoutOut"
DIST_DIR="$PROJECT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
DMG_FINAL="$DIST_DIR/ShoutOut-$VERSION.dmg"
DMG_RW="$DIST_DIR/ShoutOut-$VERSION-rw.dmg"
DMG_STAGING="$DIST_DIR/dmg-staging"
DMG_BACKGROUND="$DMG_STAGING/.background/background.png"
MOUNT_DIR=""

cleanup() {
    if [[ -n "$MOUNT_DIR" && -d "$MOUNT_DIR" ]]; then
        hdiutil detach "$MOUNT_DIR" -quiet >/dev/null 2>&1 || hdiutil detach "$MOUNT_DIR" -force -quiet >/dev/null 2>&1 || true
    fi
    rm -rf "$DMG_STAGING"
    rm -f "$DMG_RW"
}
trap cleanup EXIT

style_dmg_window() {
    osascript <<APPLESCRIPT &
with timeout of 15 seconds
    tell application "Finder"
        tell disk "$APP_NAME"
            open
            set current view of container window to icon view
            set toolbar visible of container window to false
            set statusbar visible of container window to false
            set bounds of container window to {100, 100, 780, 520}
            set theViewOptions to icon view options of container window
            set arrangement of theViewOptions to not arranged
            set icon size of theViewOptions to 96
            set label position of theViewOptions to bottom
            set background picture of theViewOptions to file ".background:background.png"
            set position of item "$APP_NAME.app" of container window to {162, 250}
            set position of item "Applications" of container window to {518, 250}
            delay 0.5
            close container window
        end tell
    end tell
end timeout
APPLESCRIPT

    local finder_pid=$!
    (
        sleep 20
        if kill -0 "$finder_pid" >/dev/null 2>&1; then
            kill "$finder_pid" >/dev/null 2>&1 || true
        fi
    ) &
    local watchdog_pid=$!

    if wait "$finder_pid"; then
        kill "$watchdog_pid" >/dev/null 2>&1 || true
        wait "$watchdog_pid" >/dev/null 2>&1 || true
        return 0
    fi

    local status=$?
    kill "$watchdog_pid" >/dev/null 2>&1 || true
    wait "$watchdog_pid" >/dev/null 2>&1 || true

    if [[ -f "$MOUNT_DIR/.DS_Store" ]]; then
        echo -e "${YELLOW}Finder styling timed out after writing .DS_Store; continuing.${NC}"
        return 0
    fi

    echo -e "${RED}Error: Finder window styling failed before writing .DS_Store.${NC}"
    return "$status"
}

detach_dmg() {
    hdiutil detach "$MOUNT_DIR" -quiet || hdiutil detach "$MOUNT_DIR" -force -quiet
    MOUNT_DIR=""
}

detach_existing_app_volumes() {
    local volume
    while IFS= read -r volume; do
        hdiutil detach "$volume" -quiet >/dev/null 2>&1 || hdiutil detach "$volume" -force -quiet >/dev/null 2>&1 || true
    done < <(
        hdiutil info \
            | awk -F '\t' -v app="$APP_NAME" '$NF == "/Volumes/" app || $NF ~ "^/Volumes/" app " [0-9]+$" { print $NF }'
    )
}

echo -e "${BLUE}Creating DMG installer for $APP_NAME v$VERSION...${NC}"

# Check if app bundle exists
if [ ! -d "$APP_BUNDLE" ]; then
    echo -e "${RED}Error: App bundle not found at $APP_BUNDLE${NC}"
    echo -e "${RED}Run ./scripts/build-app.sh first${NC}"
    exit 1
fi

# Clean previous DMG artifacts
rm -f "$DMG_FINAL"
rm -f "$DMG_RW"
rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"

# Create DMG
echo -e "${BLUE}Preparing DMG staging directory...${NC}"
ditto "$APP_BUNDLE" "$DMG_STAGING/$APP_NAME.app"
ln -s /Applications "$DMG_STAGING/Applications"
mkdir -p "$DMG_STAGING/.background"
"$SCRIPT_DIR/render-dmg-background.swift" \
    "$DMG_BACKGROUND" \
    "$PROJECT_DIR/Resources/CrabSprites/idle-1.png"

echo -e "${BLUE}Creating writable DMG image...${NC}"
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$DMG_STAGING" \
    -ov \
    -format UDRW \
    "$DMG_RW"

echo -e "${BLUE}Styling DMG Finder window...${NC}"
detach_existing_app_volumes
MOUNT_OUTPUT=$(hdiutil attach "$DMG_RW" -readwrite -noverify -noautoopen)
MOUNT_DIR=$(echo "$MOUNT_OUTPUT" | awk -F '\t' '/\/Volumes\// {print $NF; exit}')
if [[ -z "$MOUNT_DIR" || ! -d "$MOUNT_DIR" ]]; then
    echo -e "${RED}Error: Could not mount writable DMG for styling.${NC}"
    echo "$MOUNT_OUTPUT"
    exit 1
fi

SetFile -a V "$MOUNT_DIR/.background" >/dev/null 2>&1 || true
style_dmg_window

for _ in {1..10}; do
    if [[ -f "$MOUNT_DIR/.DS_Store" ]]; then
        break
    fi
    sleep 0.5
done

if [[ ! -f "$MOUNT_DIR/.background/background.png" || ! -f "$MOUNT_DIR/.DS_Store" ]]; then
    echo -e "${RED}Error: Styled DMG is missing background assets or Finder layout metadata.${NC}"
    exit 1
fi

sync
detach_dmg

echo -e "${BLUE}Creating compressed DMG image...${NC}"
hdiutil convert "$DMG_RW" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -ov \
    -o "$DMG_FINAL"

echo -e "${GREEN}DMG created: $DMG_FINAL${NC}"
hdiutil verify "$DMG_FINAL"

FILE_SIZE=$(du -h "$DMG_FINAL" | cut -f1)
echo -e "${GREEN}File size: $FILE_SIZE${NC}"

# Code sign DMG if identity is set
if [[ -n "${CODE_SIGN_IDENTITY:-}" ]]; then
    echo -e "${BLUE}Code signing DMG...${NC}"
    codesign --force --sign "$CODE_SIGN_IDENTITY" "$DMG_FINAL"
    echo -e "${GREEN}DMG code signing complete!${NC}"
    codesign --verify --verbose=2 "$DMG_FINAL"

    if [ "${SKIP_NOTARIZE:-false}" != "true" ]; then
        echo -e "${BLUE}Submitting DMG for notarization...${NC}"
        NOTARIZE_OUTPUT=$(xcrun notarytool submit "$DMG_FINAL" \
            --keychain-profile "$NOTARY_PROFILE" \
            --wait --timeout 30m 2>&1) || true

        echo "$NOTARIZE_OUTPUT"

        SUBMISSION_ID=$(echo "$NOTARIZE_OUTPUT" | grep "  id:" | head -1 | awk '{print $2}')

        if echo "$NOTARIZE_OUTPUT" | grep -q "status: Accepted"; then
            echo -e "${BLUE}Stapling notarization ticket to DMG...${NC}"
            xcrun stapler staple "$DMG_FINAL"
            echo -e "${GREEN}DMG notarization complete!${NC}"
        else
            if [ -n "$SUBMISSION_ID" ]; then
                echo -e "${YELLOW}Fetching notarization log...${NC}"
                xcrun notarytool log "$SUBMISSION_ID" --keychain-profile "$NOTARY_PROFILE" 2>&1 || true
            fi

            echo -e "${RED}DMG notarization failed or timed out.${NC}"
            exit 1
        fi
    fi
else
    echo -e "${YELLOW}No CODE_SIGN_IDENTITY set. DMG will be unsigned and not notarized.${NC}"
fi

echo -e "${GREEN}Done! Distribute: $DMG_FINAL${NC}"
