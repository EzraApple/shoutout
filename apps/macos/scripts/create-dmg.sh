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
DMG_STAGING="$DIST_DIR/dmg-staging"

cleanup() {
    rm -rf "$DMG_STAGING"
}
trap cleanup EXIT

echo -e "${BLUE}Creating DMG installer for $APP_NAME v$VERSION...${NC}"

# Check if app bundle exists
if [ ! -d "$APP_BUNDLE" ]; then
    echo -e "${RED}Error: App bundle not found at $APP_BUNDLE${NC}"
    echo -e "${RED}Run ./scripts/build-app.sh first${NC}"
    exit 1
fi

# Clean previous DMG artifacts
rm -f "$DMG_FINAL"
rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"

# Create DMG
echo -e "${BLUE}Preparing DMG staging directory...${NC}"
ditto "$APP_BUNDLE" "$DMG_STAGING/$APP_NAME.app"
ln -s /Applications "$DMG_STAGING/Applications"

echo -e "${BLUE}Creating compressed DMG image...${NC}"
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$DMG_STAGING" \
    -ov \
    -format UDZO \
    "$DMG_FINAL"

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
