#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="${SHOUT_OUT_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
REPO="${SHOUT_OUT_REPO:-EzraApple/shout-out}"
WORKFLOW="${SHOUT_OUT_WORKFLOW:-macos.yml}"
BRANCH="${SHOUT_OUT_BRANCH:-main}"
ARTIFACT_NAME="${SHOUT_OUT_ARTIFACT_NAME:-Shout-Out-app}"
APP_NAME="Shout Out"
BUNDLE_ID="com.ezraapple.shoutout"
INSTALL_DIR="${HOME}/Applications"
INSTALL_PATH="${INSTALL_DIR}/${APP_NAME}.app"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/shout-out-install.XXXXXX")"

cleanup() {
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

install_bundle() {
    local app_bundle="$1"

    if [[ -n "${CODE_SIGN_IDENTITY:-}" ]]; then
        codesign --force --deep --sign "$CODE_SIGN_IDENTITY" \
            --entitlements "${REPO_ROOT}/macos/Resources/ShoutOut.entitlements" \
            --options runtime \
            "$app_bundle"
    fi

    pkill -x ShoutOut >/dev/null 2>&1 || true
    mkdir -p "$INSTALL_DIR"
    rm -rf "$INSTALL_PATH"
    cp -R "$app_bundle" "$INSTALL_PATH"
    xattr -dr com.apple.quarantine "$INSTALL_PATH" >/dev/null 2>&1 || true

    defaults write "$BUNDLE_ID" requestPermissionsOnLaunch -bool true
    open "$INSTALL_PATH"
}

download_latest_artifact() {
    command -v gh >/dev/null 2>&1 || return 1

    local run_id="${SHOUT_OUT_RUN_ID:-}"
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
