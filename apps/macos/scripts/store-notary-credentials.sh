#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ROOT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"

for ENV_FILE in "$ROOT_DIR/.env" "$PROJECT_DIR/.env"; do
    if [[ -f "$ENV_FILE" ]]; then
        set -a
        # shellcheck disable=SC1090
        source "$ENV_FILE"
        set +a
        break
    fi
done

GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

PROFILE="${NOTARY_PROFILE:-notarytool-profile}"
APPLE_ID_VALUE="${APPLE_ID:-}"
TEAM_ID_VALUE="${TEAM_ID:-}"

if [[ -z "$APPLE_ID_VALUE" ]]; then
    echo -e "${RED}APPLE_ID is not set.${NC}" >&2
    echo "Add APPLE_ID=\"you@example.com\" to .env, then rerun this script." >&2
    exit 1
fi

if [[ -z "$TEAM_ID_VALUE" ]]; then
    echo -e "${RED}TEAM_ID is not set.${NC}" >&2
    echo "Add TEAM_ID=\"PD5XJP4VLW\" to .env, then rerun this script." >&2
    exit 1
fi

echo -e "${BLUE}Storing notarytool profile: $PROFILE${NC}"
echo -e "${YELLOW}Use an Apple app-specific password when prompted, not your normal Apple ID password.${NC}"
xcrun notarytool store-credentials "$PROFILE" \
    --apple-id "$APPLE_ID_VALUE" \
    --team-id "$TEAM_ID_VALUE"

echo -e "${GREEN}Stored notarytool credentials.${NC}"
echo "Verify with: make release-preflight"
