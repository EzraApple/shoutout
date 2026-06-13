#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="${SHOUTOUT_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
REPO="${SHOUTOUT_REPO:-EzraApple/shoutout}"
WORKFLOW="${SHOUTOUT_WORKFLOW:-macos.yml}"
BRANCH="${SHOUTOUT_BRANCH:-main}"
ARTIFACT_NAME="${SHOUTOUT_ARTIFACT_NAME:-ShoutOut-app}"
APP_NAME="ShoutOut"
BUNDLE_ID="com.ezraapple.shoutout"
INSTALL_DIR="${HOME}/Applications"
INSTALL_PATH="${INSTALL_DIR}/${APP_NAME}.app"
LEGACY_INSTALL_PATH="${INSTALL_DIR}/Shout Out.app"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/shoutout-install.XXXXXX")"

cleanup() {
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

reset_hotkey_permissions_if_existing_install_used_unstable_signature() {
    [[ -d "$INSTALL_PATH" ]] || return 0

    local requirement
    requirement="$(codesign -d -r- "$INSTALL_PATH" 2>&1 || true)"
    if [[ "$requirement" == *"cdhash"* && "$requirement" != *"identifier \"${BUNDLE_ID}\""* ]]; then
        tccutil reset Accessibility "$BUNDLE_ID" >/dev/null 2>&1 || true
        tccutil reset ListenEvent "$BUNDLE_ID" >/dev/null 2>&1 || true
    fi
}

install_bundle() {
    local app_bundle="$1"

    if [[ -n "${CODE_SIGN_IDENTITY:-}" ]]; then
        codesign --force --deep --sign "$CODE_SIGN_IDENTITY" \
            --entitlements "${REPO_ROOT}/macos/Resources/ShoutOut.entitlements" \
            --options runtime \
            "$app_bundle"
    else
        codesign --force --deep --sign - \
            --entitlements "${REPO_ROOT}/macos/Resources/ShoutOut.entitlements" \
            --requirements "=designated => identifier \"${BUNDLE_ID}\"" \
            "$app_bundle"
    fi

    pkill -x ShoutOut >/dev/null 2>&1 || true
    reset_hotkey_permissions_if_existing_install_used_unstable_signature
    mkdir -p "$INSTALL_DIR"
    rm -rf "$LEGACY_INSTALL_PATH"
    rm -rf "$INSTALL_PATH"
    cp -R "$app_bundle" "$INSTALL_PATH"
    xattr -dr com.apple.quarantine "$INSTALL_PATH" >/dev/null 2>&1 || true

    defaults write "$BUNDLE_ID" requestPermissionsOnLaunch -bool true
    if ! open -n "$INSTALL_PATH"; then
        "${INSTALL_PATH}/Contents/MacOS/ShoutOut" >/dev/null 2>&1 &
    fi
}

download_latest_artifact() {
    command -v gh >/dev/null 2>&1 || return 1

    local run_id="${SHOUTOUT_RUN_ID:-}"
    if [[ -z "$run_id" ]]; then
        run_id="$(
            gh run list \
                --repo "$REPO" \
                --workflow "$WORKFLOW" \
                --branch "$BRANCH" \
                --status success \
                --limit 1 \
                --json databaseId \
                --jq '.[0].databaseId'
        )"
    fi

    [[ -n "$run_id" && "$run_id" != "null" ]] || return 1

    gh run download "$run_id" \
        --repo "$REPO" \
        --name "$ARTIFACT_NAME" \
        --dir "$WORK_DIR"

    ditto -x -k "${WORK_DIR}/ShoutOut-app.zip" "$WORK_DIR"
    [[ -d "${WORK_DIR}/${APP_NAME}.app" ]]
}

build_locally() {
    (
        cd "${REPO_ROOT}/macos"
        UNIVERSAL=false SKIP_NOTARIZE=true ./scripts/build-app.sh
    )
}

if download_latest_artifact; then
    install_bundle "${WORK_DIR}/${APP_NAME}.app"
else
    build_locally
    install_bundle "${REPO_ROOT}/macos/dist/${APP_NAME}.app"
fi
