#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ROOT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"

PRESERVED_ENV_VALUES=()
for KEY in \
    SPARKLE_ARCHIVES_DIR \
    SPARKLE_DOWNLOAD_URL_PREFIX \
    SPARKLE_RELEASE_NOTES_URL_PREFIX \
    SPARKLE_PRODUCT_LINK \
    SPARKLE_KEY_ACCOUNT \
    SPARKLE_MAXIMUM_VERSIONS \
    SPARKLE_PRIVATE_ED_KEY \
    SPARKLE_WEB_PUBLIC_DIR \
    SPARKLE_STAGE_WEB_PUBLIC \
    SPARKLE_FEED_URL; do
    if [[ -n "${!KEY+x}" ]]; then
        PRESERVED_ENV_VALUES+=("$KEY=${!KEY}")
    fi
done

for ENV_FILE in "$ROOT_DIR/.env" "$PROJECT_DIR/.env"; do
    if [[ -f "$ENV_FILE" ]]; then
        set -a
        # shellcheck disable=SC1090
        source "$ENV_FILE"
        set +a
        break
    fi
done

for PAIR in "${PRESERVED_ENV_VALUES[@]}"; do
    export "$PAIR"
done

GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

tool_path() {
    local tool="$1"
    local path
    path="$(find "$PROJECT_DIR/.build/artifacts/sparkle/Sparkle/bin" -type f -name "$tool" -print -quit 2>/dev/null || true)"
    if [[ -z "$path" ]]; then
        echo -e "${BLUE}Resolving Sparkle tools...${NC}" >&2
        (cd "$PROJECT_DIR" && swift build --product ShoutOut >/dev/null)
        path="$(find "$PROJECT_DIR/.build/artifacts/sparkle/Sparkle/bin" -type f -name "$tool" -print -quit 2>/dev/null || true)"
    fi

    if [[ -z "$path" ]]; then
        echo -e "${RED}Could not find Sparkle tool: $tool${NC}" >&2
        exit 1
    fi

    printf '%s\n' "$path"
}

VERSION="$(plutil -extract CFBundleShortVersionString raw -o - "$PROJECT_DIR/Resources/Info.plist" 2>/dev/null || true)"
if [[ -z "$VERSION" ]]; then
    echo -e "${RED}Could not read CFBundleShortVersionString from Info.plist.${NC}" >&2
    exit 1
fi

DMG_PATH="$PROJECT_DIR/dist/ShoutOut-$VERSION.dmg"
if [[ ! -f "$DMG_PATH" ]]; then
    echo -e "${RED}Missing DMG: $DMG_PATH${NC}" >&2
    echo "Run UNIVERSAL=true make release-dmg before generating the appcast." >&2
    exit 1
fi

ARCHIVES_DIR="${SPARKLE_ARCHIVES_DIR:-$PROJECT_DIR/dist/sparkle}"
DOWNLOAD_URL_PREFIX="${SPARKLE_DOWNLOAD_URL_PREFIX:-https://shoutout.sh/releases/}"
RELEASE_NOTES_URL_PREFIX="${SPARKLE_RELEASE_NOTES_URL_PREFIX:-$DOWNLOAD_URL_PREFIX}"
PRODUCT_LINK="${SPARKLE_PRODUCT_LINK:-https://shoutout.sh}"
ACCOUNT="${SPARKLE_KEY_ACCOUNT:-ed25519}"

mkdir -p "$ARCHIVES_DIR"
cp "$DMG_PATH" "$ARCHIVES_DIR/$(basename "$DMG_PATH")"

NOTES_PATH="$ARCHIVES_DIR/ShoutOut-$VERSION.md"
if [[ ! -f "$NOTES_PATH" ]]; then
    cat > "$NOTES_PATH" <<EOF
# ShoutOut $VERSION

- Local-first macOS dictation update.
- Signed and notarized DMG release.
EOF
fi

GENERATE_APPCAST="$(tool_path generate_appcast)"
ARGS=(
    --account "$ACCOUNT"
    --download-url-prefix "$DOWNLOAD_URL_PREFIX"
    --release-notes-url-prefix "$RELEASE_NOTES_URL_PREFIX"
    --link "$PRODUCT_LINK"
    --maximum-versions "${SPARKLE_MAXIMUM_VERSIONS:-5}"
    "$ARCHIVES_DIR"
)

echo -e "${BLUE}Generating Sparkle appcast in $ARCHIVES_DIR...${NC}"
if [[ -n "${SPARKLE_PRIVATE_ED_KEY:-}" ]]; then
    printf '%s' "$SPARKLE_PRIVATE_ED_KEY" | "$GENERATE_APPCAST" --ed-key-file - "${ARGS[@]}"
else
    "$GENERATE_APPCAST" "${ARGS[@]}"
fi

if [[ -f "$ARCHIVES_DIR/appcast.xml" ]]; then
    echo -e "${GREEN}Appcast ready: $ARCHIVES_DIR/appcast.xml${NC}"
    WEB_PUBLIC_DIR="${SPARKLE_WEB_PUBLIC_DIR:-$ROOT_DIR/apps/web/public}"
    if [[ "${SPARKLE_STAGE_WEB_PUBLIC:-true}" == "true" && -d "$WEB_PUBLIC_DIR" ]]; then
        mkdir -p "$WEB_PUBLIC_DIR/releases"
        cp "$ARCHIVES_DIR/appcast.xml" "$WEB_PUBLIC_DIR/appcast.xml"
        cp "$ARCHIVES_DIR/$(basename "$DMG_PATH")" "$WEB_PUBLIC_DIR/releases/$(basename "$DMG_PATH")"
        cp "$NOTES_PATH" "$WEB_PUBLIC_DIR/releases/$(basename "$NOTES_PATH")"
        echo -e "${GREEN}Staged appcast: $WEB_PUBLIC_DIR/appcast.xml${NC}"
        echo -e "${GREEN}Staged DMG: $WEB_PUBLIC_DIR/releases/$(basename "$DMG_PATH")${NC}"
        echo -e "${GREEN}Staged release notes: $WEB_PUBLIC_DIR/releases/$(basename "$NOTES_PATH")${NC}"
    else
        echo -e "${YELLOW}Skipped web public staging.${NC}"
    fi

    echo -e "${GREEN}Publish appcast.xml at ${SPARKLE_FEED_URL:-https://shoutout.sh/appcast.xml}.${NC}"
    echo -e "${GREEN}Publish $(basename "$DMG_PATH") at ${DOWNLOAD_URL_PREFIX}$(basename "$DMG_PATH").${NC}"
    echo -e "${GREEN}Publish $(basename "$NOTES_PATH") at ${RELEASE_NOTES_URL_PREFIX}$(basename "$NOTES_PATH").${NC}"
else
    echo -e "${RED}generate_appcast completed but appcast.xml was not found.${NC}" >&2
    exit 1
fi
