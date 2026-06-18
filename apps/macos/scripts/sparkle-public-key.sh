#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

BLUE='\033[0;34m'
GREEN='\033[0;32m'
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
        echo "Could not find Sparkle tool: $tool" >&2
        exit 1
    fi

    printf '%s\n' "$path"
}

GENERATE_KEYS="$(tool_path generate_keys)"
ACCOUNT="${SPARKLE_KEY_ACCOUNT:-ed25519}"

echo -e "${BLUE}Sparkle public key for account: ${ACCOUNT}${NC}" >&2
"$GENERATE_KEYS" --account "$ACCOUNT" "$@"
echo -e "${GREEN}Add the printed SUPublicEDKey value to SPARKLE_PUBLIC_ED_KEY in .env.${NC}" >&2
