#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="${SHOUT_OUT_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
MACOS_DIR="$REPO_ROOT/macos"

pass_count=0
fail_count=0

record_pass() {
  pass_count=$((pass_count + 1))
  printf 'ok - %s\n' "$1"
}

record_fail() {
  fail_count=$((fail_count + 1))
  printf 'not ok - %s\n' "$1"
}

assert_contains() {
  local name="$1"
  local file="$2"
  local pattern="$3"
  if command -v rg >/dev/null 2>&1; then
    if rg -q "$pattern" "$file"; then
      record_pass "$name"
    else
      record_fail "$name"
    fi
    return
  fi

  if grep -Eq "$pattern" "$file"; then
    record_pass "$name"
  else
    record_fail "$name"
  fi
}

assert_plist_value() {
  local name="$1"
  local file="$2"
  local key="$3"
  local expected="$4"
  local actual
  actual="$(plutil -extract "$key" raw -o - "$file" 2>/dev/null || true)"
  if [[ "$actual" == "$expected" ]]; then
    record_pass "$name"
  else
    record_fail "$name"
  fi
}

assert_plist_key() {
  local name="$1"
  local file="$2"
  local key="$3"
  if plutil -extract "$key" raw -o - "$file" >/dev/null 2>&1; then
    record_pass "$name"
  else
    record_fail "$name"
  fi
}

assert_contains "README names Shout Out" "$REPO_ROOT/README.md" "^# Shout Out"
assert_contains "README documents make install" "$REPO_ROOT/README.md" "make install"
assert_contains "README preserves MIT attribution" "$REPO_ROOT/README.md" "Inputalk"
assert_contains "README documents Microphone" "$REPO_ROOT/README.md" "Microphone"
assert_contains "README documents Accessibility" "$REPO_ROOT/README.md" "Accessibility"
assert_contains "README documents Input Monitoring" "$REPO_ROOT/README.md" "Input Monitoring"
assert_contains "README documents permission reset" "$REPO_ROOT/README.md" "make reset-permissions"
assert_contains "README documents pinned Actions install" "$REPO_ROOT/README.md" "SHOUT_OUT_RUN_ID"
assert_contains "README documents audio input recovery" "$REPO_ROOT/README.md" "AirPods"
assert_contains "README documents runtime logs" "$REPO_ROOT/README.md" "runtime.log"
assert_contains "README documents custom dictionary entries" "$REPO_ROOT/README.md" "custom dictionary entries"
assert_contains "Makefile has install target" "$REPO_ROOT/Makefile" "^install:"
assert_contains "Makefile has local install target" "$REPO_ROOT/Makefile" "^install-local:"
assert_contains "Install script downloads CI artifact" "$REPO_ROOT/scripts/install-latest.sh" "gh run download"
assert_contains "Install script uses stable local signing" "$REPO_ROOT/scripts/install-latest.sh" "designated => identifier"
assert_contains "Install script resets stale hotkey permissions" "$REPO_ROOT/scripts/install-latest.sh" "reset_hotkey_permissions_if_existing_install_used_unstable_signature"
assert_contains "Makefile can reset TCC permissions" "$REPO_ROOT/Makefile" "reset-permissions"
assert_contains "Package name is ShoutOut" "$MACOS_DIR/Package.swift" 'name: "ShoutOut"'
assert_contains "Executable target is ShoutOut" "$MACOS_DIR/Package.swift" 'name: "ShoutOut"'
assert_contains "Library target is ShoutOutCore" "$MACOS_DIR/Package.swift" 'name: "ShoutOutCore"'
assert_contains "Test target is ShoutOutCoreTests" "$MACOS_DIR/Package.swift" 'name: "ShoutOutCoreTests"'
assert_plist_value "Info.plist bundle name is Shout Out" "$MACOS_DIR/Resources/Info.plist" "CFBundleName" "Shout Out"
assert_plist_value "Info.plist executable is ShoutOut" "$MACOS_DIR/Resources/Info.plist" "CFBundleExecutable" "ShoutOut"
assert_plist_value "Info.plist bundle id is com.ezraapple.shoutout" "$MACOS_DIR/Resources/Info.plist" "CFBundleIdentifier" "com.ezraapple.shoutout"
assert_plist_key "Info.plist has microphone usage text" "$MACOS_DIR/Resources/Info.plist" "NSMicrophoneUsageDescription"
assert_plist_key "Info.plist has accessibility usage text" "$MACOS_DIR/Resources/Info.plist" "NSAccessibilityUsageDescription"
assert_plist_key "Info.plist has input monitoring usage text" "$MACOS_DIR/Resources/Info.plist" "NSInputMonitoringUsageDescription"
assert_contains "Entitlements allow audio input" "$MACOS_DIR/Resources/ShoutOut.entitlements" "com.apple.security.device.audio-input"
assert_contains "Build script builds Shout Out.app" "$MACOS_DIR/scripts/build-app.sh" 'APP_NAME="Shout Out"'
assert_contains "Build script has executable name" "$MACOS_DIR/scripts/build-app.sh" 'EXECUTABLE_NAME="ShoutOut"'
assert_contains "Build script signs for local use" "$MACOS_DIR/scripts/build-app.sh" "Ad-hoc signing"
assert_contains "Build script uses stable local signing" "$MACOS_DIR/scripts/build-app.sh" "designated => identifier"
assert_contains "Transcription imports core" "$MACOS_DIR/Sources/Services/TranscriptionService.swift" "import ShoutOutCore"
assert_contains "Transcription returns result shape" "$MACOS_DIR/Sources/Services/TranscriptionService.swift" "DictationResult"
assert_contains "Settings expose dictionary" "$MACOS_DIR/Sources/Views/SettingsView.swift" "Dictionary"
assert_contains "Settings expose insights" "$MACOS_DIR/Sources/Views/SettingsView.swift" "Insights"
assert_contains "Settings expose audio ducking" "$MACOS_DIR/Sources/Views/SettingsView.swift" "Dim system audio"
assert_contains "Settings expose indicator picker" "$MACOS_DIR/Sources/Views/SettingsView.swift" "Indicator"
assert_contains "Permission manager checks input monitoring" "$MACOS_DIR/Sources/Services/PermissionManager.swift" "CGPreflightListenEventAccess"
assert_contains "App delegate requests permissions sequentially" "$MACOS_DIR/Sources/AppDelegate.swift" "continuePermissionSetupIfRequested"
assert_contains "Hotkey starts capture immediately" "$MACOS_DIR/Sources/Services/HotkeyManager.swift" "start audio capture immediately"
assert_contains "App delegate tracks committed recordings" "$MACOS_DIR/Sources/AppDelegate.swift" "recordingIsCommitted"
assert_contains "App delegate discards quick releases" "$MACOS_DIR/Sources/AppDelegate.swift" "quickRelease"
assert_contains "Audio recorder allows fast snippets" "$MACOS_DIR/Sources/Services/AudioRecorder.swift" "minimumSamples = 3200"
assert_contains "Audio recorder logs input format" "$MACOS_DIR/Sources/Services/AudioRecorder.swift" "record input format"
assert_contains "Audio converter provides each tap buffer once" "$MACOS_DIR/Sources/Services/AudioRecorder.swift" "didProvideInput"
assert_contains "Audio signal analysis gates silence" "$MACOS_DIR/Sources/Core/AudioSignalAnalysis.swift" "hasSpeechLikeAudio"
assert_contains "App delegate blocks silent recordings" "$MACOS_DIR/Sources/AppDelegate.swift" "record stopped silent"
assert_contains "App delegate queues transcription jobs" "$MACOS_DIR/Sources/AppDelegate.swift" "transcriptionQueueTail"
assert_contains "App delegate tracks pending transcriptions" "$MACOS_DIR/Sources/AppDelegate.swift" "pendingTranscriptionCount"
assert_contains "App delegate records usage stats" "$MACOS_DIR/Sources/AppDelegate.swift" "usageStats"
assert_contains "App delegate ducks audio" "$MACOS_DIR/Sources/AppDelegate.swift" "audioDucker"
assert_contains "App delegate defaults to crab overlay" "$MACOS_DIR/Sources/AppDelegate.swift" "OverlayStyle.crab"
assert_contains "App delegate keeps overlay above apps" "$MACOS_DIR/Sources/AppDelegate.swift" "panel.level = .statusBar"
assert_contains "App delegate supports overlay preview mode" "$MACOS_DIR/Sources/AppDelegate.swift" "SHOUTOUT_OVERLAY_PREVIEW"
assert_contains "App delegate creates overlay with concrete frame" "$MACOS_DIR/Sources/AppDelegate.swift" "initialIndicatorFrame"
assert_contains "App delegate logs preview overlay visibility" "$MACOS_DIR/Sources/AppDelegate.swift" "shoutout-overlay-preview.log"
assert_contains "App delegate can snapshot overlay previews" "$MACOS_DIR/Sources/AppDelegate.swift" "SHOUTOUT_OVERLAY_SNAPSHOT_PATH"
assert_contains "Crab overlay has boom mic" "$MACOS_DIR/Sources/Views/FloatingIndicator.swift" "boomMic"
assert_contains "Crab overlay shows processing badge" "$MACOS_DIR/Sources/Views/FloatingIndicator.swift" "processingBadge"
assert_contains "Crab overlay animates idle crawl" "$MACOS_DIR/Sources/Views/FloatingIndicator.swift" "animateIdleCrawl"
assert_contains "Boom crab stays still" "$MACOS_DIR/Sources/Views/FloatingIndicator.swift" "if showsBoomMic"
assert_contains "Boom crab scale matches idle crab" "$MACOS_DIR/Sources/Views/FloatingIndicator.swift" "boomScale"
assert_contains "Crab idle uses stable frame cycle" "$MACOS_DIR/Sources/Views/FloatingIndicator.swift" "stableFrameIndices"
assert_contains "Classic overlay has compact layout" "$MACOS_DIR/Sources/Views/FloatingIndicator.swift" "ClassicOverlayLayout"
assert_contains "Crab overlay has visible dark-surface halo" "$MACOS_DIR/Sources/Views/FloatingIndicator.swift" "white.opacity"

if [[ "${SKIP_SWIFTPM:-false}" == "true" ]]; then
  printf 'skip - SwiftPM checks skipped by SKIP_SWIFTPM=true\n'
else
  if (cd "$MACOS_DIR" && swift test); then
    record_pass "Swift unit tests pass"
  else
    record_fail "Swift unit tests pass"
  fi

  if (cd "$MACOS_DIR" && swift build); then
    record_pass "Swift package builds"
  else
    record_fail "Swift package builds"
  fi
fi

printf '\n%d passed, %d failed\n' "$pass_count" "$fail_count"
if [[ "$fail_count" -gt 0 ]]; then
  exit 1
fi
