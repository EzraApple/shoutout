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

fail_count=0
warn_count=0

pass() {
    printf "${GREEN}ok${NC} - %s\n" "$1"
}

warn() {
    warn_count=$((warn_count + 1))
    printf "${YELLOW}warn${NC} - %s\n" "$1"
}

fail() {
    fail_count=$((fail_count + 1))
    printf "${RED}not ok${NC} - %s\n" "$1"
}

has_command() {
    command -v "$1" >/dev/null 2>&1
}

echo -e "${BLUE}ShoutOut release preflight${NC}"
echo ""

for tool in xcodebuild swift security codesign xcrun hdiutil ditto plutil; do
    if has_command "$tool"; then
        pass "$tool is available"
    else
        fail "$tool is missing"
    fi
done

if xcodebuild -version >/tmp/shoutout-xcode-version.txt 2>/tmp/shoutout-xcode-version.err; then
    xcode_version="$(head -1 /tmp/shoutout-xcode-version.txt)"
    pass "Xcode license accepted (${xcode_version})"
else
    fail "Xcode is not usable; run: sudo xcodebuild -license"
fi

if swift --version >/tmp/shoutout-swift-version.txt 2>/dev/null; then
    swift_version="$(head -1 /tmp/shoutout-swift-version.txt)"
    pass "Swift is available (${swift_version})"
else
    fail "Swift is not available"
fi

if [[ -f "$PROJECT_DIR/Resources/Info.plist" ]]; then
    version="$(plutil -extract CFBundleShortVersionString raw -o - "$PROJECT_DIR/Resources/Info.plist" 2>/dev/null || true)"
    bundle_id="$(plutil -extract CFBundleIdentifier raw -o - "$PROJECT_DIR/Resources/Info.plist" 2>/dev/null || true)"
    if [[ -n "$version" && -n "$bundle_id" ]]; then
        pass "Info.plist version ${version}, bundle id ${bundle_id}"
    else
        fail "Info.plist is missing version or bundle id"
    fi
else
    fail "Info.plist is missing"
fi

identity_output="$(security find-identity -p codesigning -v 2>/dev/null || true)"
developer_id_identities="$(
    printf '%s\n' "$identity_output" \
        | awk -F'"' '/Developer ID Application:/ { print $2 }'
)"
developer_id_count="$(
    printf '%s\n' "$developer_id_identities" \
        | awk 'NF { count += 1 } END { print count + 0 }'
)"

if [[ "$developer_id_count" -eq 0 ]]; then
    fail "No Developer ID Application certificate found in Keychain"
    echo "       Create one in Xcode > Settings > Accounts > Manage Certificates > + > Developer ID Application"
elif [[ -n "${CODE_SIGN_IDENTITY:-}" ]]; then
    if printf '%s\n' "$developer_id_identities" | grep -Fxq "$CODE_SIGN_IDENTITY"; then
        pass "CODE_SIGN_IDENTITY matches an installed Developer ID certificate"
    else
        fail "CODE_SIGN_IDENTITY is set but does not match an installed Developer ID certificate"
        echo "       Installed Developer ID identities:"
        printf '%s\n' "$developer_id_identities" | sed 's/^/       - /'
    fi
else
    if [[ "$developer_id_count" -eq 1 ]]; then
        only_identity="$(printf '%s\n' "$developer_id_identities" | awk 'NF { print; exit }')"
        warn "CODE_SIGN_IDENTITY is not set; add this to .env:"
        echo "       CODE_SIGN_IDENTITY=\"$only_identity\""
    else
        fail "Multiple Developer ID certificates found and CODE_SIGN_IDENTITY is not set"
        printf '%s\n' "$developer_id_identities" | sed 's/^/       - /'
    fi
fi

notary_profile="${NOTARY_PROFILE:-notarytool-profile}"
notary_apple_id="${APPLE_ID:-you@example.com}"
notary_team_id="${TEAM_ID:-}"
identity_for_team="${CODE_SIGN_IDENTITY:-${only_identity:-}}"
if [[ -z "$notary_team_id" && -n "$identity_for_team" ]]; then
    notary_team_id="$(
        printf '%s\n' "$identity_for_team" \
            | sed -n 's/.*(\([^)]*\)).*/\1/p'
    )"
fi
if [[ -z "$notary_team_id" ]]; then
    notary_team_id="TEAMID"
fi

if xcrun notarytool history --keychain-profile "$notary_profile" >/tmp/shoutout-notary-history.txt 2>/tmp/shoutout-notary-history.err; then
    pass "notarytool profile works (${notary_profile})"
else
    fail "notarytool profile is missing or invalid (${notary_profile})"
    echo "       Create it with:"
    echo "       xcrun notarytool store-credentials ${notary_profile} --apple-id \"${notary_apple_id}\" --team-id \"${notary_team_id}\""
fi

if [[ -n "${SPARKLE_PUBLIC_ED_KEY:-}" && "$SPARKLE_PUBLIC_ED_KEY" != "paste SUPublicEDKey here" ]]; then
    pass "Sparkle public key is configured"
else
    warn "Sparkle public key is not configured; run: make sparkle-public-key"
fi

if [[ "${SPARKLE_FEED_URL:-https://shoutout.sh/appcast.xml}" == https://* ]]; then
    pass "Sparkle feed URL uses HTTPS (${SPARKLE_FEED_URL:-https://shoutout.sh/appcast.xml})"
else
    fail "Sparkle feed URL must use HTTPS"
fi

if [[ "${SPARKLE_DOWNLOAD_URL_PREFIX:-https://shoutout.sh/releases/}" == https://* ]]; then
    pass "Sparkle download URL prefix uses HTTPS"
else
    fail "Sparkle download URL prefix must use HTTPS"
fi

if [[ -f "$ROOT_DIR/.env" || -f "$PROJECT_DIR/.env" ]]; then
    pass ".env exists for release settings"
else
    warn "No .env found; copy .env.example to .env after the Developer ID certificate exists"
fi

echo ""
if [[ "$fail_count" -gt 0 ]]; then
    printf "${RED}%s release blocker(s), %s warning(s).${NC}\n" "$fail_count" "$warn_count"
    exit 1
fi

printf "${GREEN}Release machine is ready.%s${NC}\n" ""
echo "Run: UNIVERSAL=true make release-dmg"
