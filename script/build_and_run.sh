#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
mode="${1:---headless}"
case "$mode" in
    --headless|--gui|--verify|--debug|--logs|--telemetry) ;;
    *) echo "usage: $0 [--headless|--gui|--verify|--debug|--logs|--telemetry]" >&2; exit 2 ;;
esac
if [[ "$mode" == "--gui" ]]; then
    pkill -x ShoutOut 2>/dev/null || true
fi
cd "$root/apps/macos"
UNIVERSAL=false SKIP_NOTARIZE=true SHOUTOUT_LOCAL_TRIAL=true ./scripts/build-app.sh
export SHOUTOUT_SKIP_USER_INSTALL_RELOCATION=1
case "$mode" in
    --gui) /usr/bin/open -n "$root/apps/macos/dist/ShoutOut.app" ;;
    --verify) "$root/script/shoutout" status ;;
    --debug) lldb -- "$root/apps/macos/dist/ShoutOut.app/Contents/MacOS/ShoutOut" --cli serve ;;
    --headless|--logs|--telemetry) exec "$root/script/shoutout" serve ;;
esac
