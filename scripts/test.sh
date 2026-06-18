#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="${SHOUTOUT_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
MACOS_DIR="$REPO_ROOT/apps/macos"

SPEECH_ANALYZER_DEVELOPER_DIR=""

detect_speech_analyzer_toolchain_if_available() {
  if [[ -n "${DEVELOPER_DIR:-}" ]]; then
    return
  fi

  if swift --version 2>/dev/null | grep -Eq 'Apple Swift version (6\.[2-9]|[7-9])'; then
    return
  fi

  local clt_dir="/Library/Developer/CommandLineTools"
  if [[ -x "$clt_dir/usr/bin/swift" ]] \
    && DEVELOPER_DIR="$clt_dir" swift --version 2>/dev/null \
      | grep -Eq 'Apple Swift version (6\.[2-9]|[7-9])'; then
    SPEECH_ANALYZER_DEVELOPER_DIR="$clt_dir"
    printf 'Using current Command Line Tools for Apple Dictation support when building.\n'
  fi
}

run_with_speech_analyzer_toolchain() {
  if [[ -n "${DEVELOPER_DIR:-}" || -z "$SPEECH_ANALYZER_DEVELOPER_DIR" ]]; then
    "$@"
    return
  fi

  DEVELOPER_DIR="$SPEECH_ANALYZER_DEVELOPER_DIR" "$@"
}

run_swift_tests() {
  if (cd "$MACOS_DIR" && swift test); then
    return
  fi

  if [[ -n "$SPEECH_ANALYZER_DEVELOPER_DIR" ]]; then
    (cd "$MACOS_DIR" && DEVELOPER_DIR="$SPEECH_ANALYZER_DEVELOPER_DIR" swift test)
    return
  fi

  return 1
}

detect_speech_analyzer_toolchain_if_available

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

assert_contains "README names ShoutOut" "$REPO_ROOT/README.md" "^# ShoutOut"
assert_contains "README documents make install" "$REPO_ROOT/README.md" "make install"
assert_contains "README preserves MIT attribution" "$REPO_ROOT/README.md" "Inputalk"
assert_contains "README documents Microphone" "$REPO_ROOT/README.md" "Microphone"
assert_contains "README documents Speech Recognition" "$REPO_ROOT/README.md" "Speech Recognition"
assert_contains "README documents Apple Dictation" "$REPO_ROOT/README.md" "Apple Dictation"
assert_contains "README documents Accessibility" "$REPO_ROOT/README.md" "Accessibility"
assert_contains "README documents Input Monitoring" "$REPO_ROOT/README.md" "Input Monitoring"
assert_contains "README documents pinned Actions install" "$REPO_ROOT/README.md" "SHOUTOUT_RUN_ID"
assert_contains "README links troubleshooting" "$REPO_ROOT/README.md" "TROUBLESHOOTING.md"
assert_contains "README documents custom dictionary entries" "$REPO_ROOT/README.md" "custom dictionary entries"
assert_contains "README says semantic rewrites are off by default" "$REPO_ROOT/README.md" "Semantic self-correction rewrites are off by default"
assert_contains "README documents smart spacing fallback" "$REPO_ROOT/README.md" "Smart spacing falls back"
assert_contains "Troubleshooting documents permission reset" "$REPO_ROOT/TROUBLESHOOTING.md" "make reset-permissions"
assert_contains "Troubleshooting marks agent-oriented scope" "$REPO_ROOT/TROUBLESHOOTING.md" "agents and operators"
assert_contains "Troubleshooting documents audio input recovery" "$REPO_ROOT/TROUBLESHOOTING.md" "AirPods"
assert_contains "Troubleshooting documents Speech Recognition" "$REPO_ROOT/TROUBLESHOOTING.md" "Speech Recognition"
assert_contains "Troubleshooting documents runtime logs" "$REPO_ROOT/TROUBLESHOOTING.md" "runtime.log"
assert_contains "Troubleshooting documents signal diagnosis" "$REPO_ROOT/TROUBLESHOOTING.md" "record signal rms"
assert_contains "Makefile has install target" "$REPO_ROOT/Makefile" "^install:"
assert_contains "Makefile has local install target" "$REPO_ROOT/Makefile" "^install-local:"
assert_contains "Makefile has local restart target" "$REPO_ROOT/Makefile" "^restart-local:"
assert_contains "Makefile has release DMG target" "$REPO_ROOT/Makefile" "^release-dmg:"
assert_contains "Makefile release DMG passes architecture setting" "$REPO_ROOT/Makefile" 'UNIVERSAL="\$\(UNIVERSAL\)" ./scripts/release.sh'
assert_contains "Makefile has web placeholder check" "$REPO_ROOT/Makefile" "^web-check:"
assert_contains "Makefile restart skips onboarding" "$REPO_ROOT/Makefile" "hasCompletedOnboarding"
assert_contains "Install script downloads CI artifact" "$REPO_ROOT/scripts/install-latest.sh" "gh run download"
assert_contains "Install script uses stable local signing" "$REPO_ROOT/scripts/install-latest.sh" "designated => identifier"
assert_contains "Install script resets stale hotkey permissions" "$REPO_ROOT/scripts/install-latest.sh" "reset_hotkey_permissions_if_existing_install_used_unstable_signature"
assert_contains "Makefile can reset TCC permissions" "$REPO_ROOT/Makefile" "reset-permissions"
assert_contains "Package name is ShoutOut" "$MACOS_DIR/Package.swift" 'name: "ShoutOut"'
assert_contains "Executable target is ShoutOut" "$MACOS_DIR/Package.swift" 'name: "ShoutOut"'
assert_contains "Library target is ShoutOutCore" "$MACOS_DIR/Package.swift" 'name: "ShoutOutCore"'
assert_contains "Test target is ShoutOutCoreTests" "$MACOS_DIR/Package.swift" 'name: "ShoutOutCoreTests"'
assert_plist_value "Info.plist bundle name is ShoutOut" "$MACOS_DIR/Resources/Info.plist" "CFBundleName" "ShoutOut"
assert_plist_value "Info.plist executable is ShoutOut" "$MACOS_DIR/Resources/Info.plist" "CFBundleExecutable" "ShoutOut"
assert_plist_value "Info.plist bundle id is com.ezraapple.shoutout" "$MACOS_DIR/Resources/Info.plist" "CFBundleIdentifier" "com.ezraapple.shoutout"
assert_plist_key "Info.plist has microphone usage text" "$MACOS_DIR/Resources/Info.plist" "NSMicrophoneUsageDescription"
assert_plist_key "Info.plist has speech recognition usage text" "$MACOS_DIR/Resources/Info.plist" "NSSpeechRecognitionUsageDescription"
assert_plist_key "Info.plist has accessibility usage text" "$MACOS_DIR/Resources/Info.plist" "NSAccessibilityUsageDescription"
assert_plist_key "Info.plist has input monitoring usage text" "$MACOS_DIR/Resources/Info.plist" "NSInputMonitoringUsageDescription"
assert_contains "Entitlements allow audio input" "$MACOS_DIR/Resources/ShoutOut.entitlements" "com.apple.security.device.audio-input"
assert_contains "Build script builds ShoutOut.app" "$MACOS_DIR/scripts/build-app.sh" 'APP_NAME="ShoutOut"'
assert_contains "Build script has executable name" "$MACOS_DIR/scripts/build-app.sh" 'EXECUTABLE_NAME="ShoutOut"'
assert_contains "Build script signs for local use" "$MACOS_DIR/scripts/build-app.sh" "Ad-hoc signing"
assert_contains "Build script uses stable local signing" "$MACOS_DIR/scripts/build-app.sh" "designated => identifier"
assert_contains "Build script auto-selects current CLT" "$MACOS_DIR/scripts/build-app.sh" "Command Line Tools for Apple Dictation support"
assert_contains "Release script creates DMG" "$MACOS_DIR/scripts/release.sh" "create-dmg.sh"
assert_contains "DMG script supports notarization profile" "$MACOS_DIR/scripts/create-dmg.sh" "NOTARY_PROFILE"
assert_contains "DMG script uses built-in hdiutil" "$MACOS_DIR/scripts/create-dmg.sh" "hdiutil create"
assert_contains "Web placeholder exists" "$REPO_ROOT/apps/web/index.html" "Coming soon"
assert_contains "Test script auto-selects current CLT" "$REPO_ROOT/scripts/test.sh" "Command Line Tools for Apple Dictation support"
assert_contains "Transcription imports core" "$MACOS_DIR/Sources/Services/TranscriptionService.swift" "import ShoutOutCore"
assert_contains "Transcription returns result shape" "$MACOS_DIR/Sources/Services/TranscriptionService.swift" "DictationResult"
assert_contains "Transcription records timing snapshot" "$MACOS_DIR/Sources/Services/TranscriptionService.swift" "TranscriptionTimingSnapshot"
assert_contains "Transcription supports backend selection" "$MACOS_DIR/Sources/Services/TranscriptionService.swift" "selectedBackend"
assert_contains "Transcription defaults to Apple Speech for testing" "$MACOS_DIR/Sources/Services/TranscriptionService.swift" "\\?\\? \\.appleSpeech"
assert_contains "Transcription has swappable engine protocol" "$MACOS_DIR/Sources/Services/TranscriptionBackend.swift" "protocol TranscriptionEngine"
assert_contains "Transcription exposes Apple Dictation backend" "$MACOS_DIR/Sources/Services/TranscriptionBackend.swift" "appleDictation"
assert_contains "Transcription auto-routes long Apple sessions" "$MACOS_DIR/Sources/Services/TranscriptionService.swift" "transcription autoswitch backend=appleDictation"
assert_contains "Transcription restores Apple Speech readiness after long load failure" "$MACOS_DIR/Sources/Services/TranscriptionService.swift" "modelState = \\.ready"
assert_contains "WhisperKit is behind an engine" "$MACOS_DIR/Sources/Services/WhisperKitTranscriptionEngine.swift" "WhisperKitTranscriptionEngine"
assert_contains "Apple Speech backend requires on-device recognition" "$MACOS_DIR/Sources/Services/AppleSpeechTranscriptionEngine.swift" "requiresOnDeviceRecognition = true"
assert_contains "Apple Dictation backend uses SpeechAnalyzer" "$MACOS_DIR/Sources/Services/AppleDictationTranscriptionEngine.swift" "SpeechAnalyzer"
assert_contains "Apple Dictation backend uses range reconciliation" "$MACOS_DIR/Sources/Services/AppleDictationTranscriptionEngine.swift" "TimeRangeTranscript"
assert_contains "Settings expose dictionary" "$MACOS_DIR/Sources/Views/SettingsView.swift" "Dictionary"
assert_contains "Settings expose insights" "$MACOS_DIR/Sources/Views/SettingsView.swift" "Insights"
assert_contains "Settings expose audio ducking" "$MACOS_DIR/Sources/Views/SettingsView.swift" "Dim system audio"
assert_contains "Settings expose indicator picker" "$MACOS_DIR/Sources/Views/SettingsView.swift" "Indicator"
assert_contains "Settings expose engine picker" "$MACOS_DIR/Sources/Views/SettingsView.swift" "Engine"
assert_contains "Settings expose smart spacing toggle" "$MACOS_DIR/Sources/Views/SettingsView.swift" "Smart spacing"
assert_contains "Settings expose trailing space fallback toggle" "$MACOS_DIR/Sources/Views/SettingsView.swift" "Fallback trailing space"
assert_contains "Settings expose semantic rewrite toggle" "$MACOS_DIR/Sources/Views/SettingsView.swift" "Rewrite self-corrections"
assert_contains "Settings expose latency text" "$MACOS_DIR/Sources/Views/SettingsView.swift" "Last latency"
assert_contains "Settings expose model progress bar" "$MACOS_DIR/Sources/Views/SettingsView.swift" "ModelProgressBar"
assert_contains "Onboarding exposes model progress bar" "$MACOS_DIR/Sources/Views/OnboardingView.swift" "ModelProgressBar"
assert_contains "Onboarding exposes Speech Recognition permission" "$MACOS_DIR/Sources/Views/OnboardingView.swift" "Speech Recognition"
assert_contains "Model state exposes startup progress" "$MACOS_DIR/Sources/Services/TranscriptionService.swift" "startupProgress"
assert_contains "Usage stats persist performance metrics" "$MACOS_DIR/Sources/Core/UsageStatsStore.swift" "UsagePerformanceMetrics"
assert_contains "Permission manager checks input monitoring" "$MACOS_DIR/Sources/Services/PermissionManager.swift" "CGPreflightListenEventAccess"
assert_contains "Permission manager checks speech recognition" "$MACOS_DIR/Sources/Services/PermissionManager.swift" "SFSpeechRecognizer.authorizationStatus"
assert_contains "Permission manager follows backend speech requirement" "$MACOS_DIR/Sources/Services/PermissionManager.swift" "requiresSpeechRecognitionPermission"
assert_contains "App delegate requests permissions sequentially" "$MACOS_DIR/Sources/AppDelegate.swift" "continuePermissionSetupIfRequested"
assert_contains "App delegate observes model state" "$MACOS_DIR/Sources/AppDelegate.swift" "observeModelState"
assert_contains "App delegate hides overlay before model readiness" "$MACOS_DIR/Sources/AppDelegate.swift" "modelIsReadyForOverlay"
assert_contains "App delegate has initializing menu state" "$MACOS_DIR/Sources/AppDelegate.swift" "initializing\\(progress"
assert_contains "App delegate logs dictation metrics" "$MACOS_DIR/Sources/AppDelegate.swift" "dictation metrics"
assert_contains "App delegate uses structured tail policy" "$MACOS_DIR/Sources/AppDelegate.swift" "RecordingTailPolicy"
assert_contains "App delegate logs tail grace" "$MACOS_DIR/Sources/AppDelegate.swift" "tailGraceMs"
assert_contains "Text inserter supports smart spacing" "$MACOS_DIR/Sources/Services/TextInserter.swift" "focusedTextInsertionContext"
assert_contains "Text inserter routes Codex through clipboard paste" "$MACOS_DIR/Sources/Services/TextInserter.swift" "com.openai.codex"
assert_contains "Text inserter avoids AX insertion for web shells" "$MACOS_DIR/Sources/Services/TextInserter.swift" "prefersClipboardInsertion"
assert_contains "Text inserter captures target before overlay focus" "$MACOS_DIR/Sources/AppDelegate.swift" "TextInserter.captureFocusedTarget"
assert_contains "Text inserter verifies AX insertion before success" "$MACOS_DIR/Sources/Services/TextInserter.swift" "paste accessibility unverified"
assert_contains "Text inserter uses bounded clipboard verification" "$MACOS_DIR/Sources/Services/TextInserter.swift" "waitForPasteVerification"
assert_contains "Text inserter preserves recovery clipboard on unverified paste" "$MACOS_DIR/Sources/Services/TextInserter.swift" "restore skipped reason=unverified"
assert_contains "Text inserter can post paste to captured app PID" "$MACOS_DIR/Sources/Services/TextInserter.swift" "postToPid"
assert_contains "Core supports trailing fallback" "$MACOS_DIR/Sources/Core/TextInsertionFormatter.swift" "fallbackTrailing"
assert_contains "Core formats insertion spacing" "$MACOS_DIR/Sources/Core/TextInsertionFormatter.swift" "TextInsertionFormatter"
assert_contains "WhisperKit cleans interrupted downloads" "$MACOS_DIR/Sources/Services/WhisperKitTranscriptionEngine.swift" "cleanupInterruptedDownloads"
assert_contains "WhisperKit removes transient extraction dirs" "$MACOS_DIR/Sources/Services/WhisperKitTranscriptionEngine.swift" ".extracting"
assert_contains "Postprocessor defaults semantic rewrites off" "$MACOS_DIR/Sources/Core/TextPostProcessor.swift" "cleanUpSelfCorrections: Bool = false"
assert_contains "Hotkey starts capture immediately" "$MACOS_DIR/Sources/Services/HotkeyManager.swift" "start audio capture immediately"
assert_contains "App delegate tracks committed recordings" "$MACOS_DIR/Sources/AppDelegate.swift" "recordingIsCommitted"
assert_contains "App delegate discards quick releases" "$MACOS_DIR/Sources/AppDelegate.swift" "quickRelease"
assert_contains "Audio recorder allows fast snippets" "$MACOS_DIR/Sources/Services/AudioRecorder.swift" "minimumSamples = 3200"
assert_contains "Audio recorder logs input format" "$MACOS_DIR/Sources/Services/AudioRecorder.swift" "record input format"
assert_contains "Audio converter provides each tap buffer once" "$MACOS_DIR/Sources/Services/AudioConverterInputProvider.swift" "didProvideInput"
assert_contains "Audio signal analysis gates silence" "$MACOS_DIR/Sources/Core/AudioSignalAnalysis.swift" "hasSpeechLikeAudio"
assert_contains "App delegate blocks silent recordings" "$MACOS_DIR/Sources/AppDelegate.swift" "record stopped silent"
assert_contains "App delegate starts independent transcription sessions" "$MACOS_DIR/Sources/AppDelegate.swift" "latestTranscriptionSessionID"
assert_contains "App delegate drops stale transcription sessions" "$MACOS_DIR/Sources/AppDelegate.swift" "transcription stale"
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
assert_contains "Crab overlay animates wall crab" "$MACOS_DIR/Sources/Views/FloatingIndicator.swift" "animateCrab"
assert_contains "Boom crab stays still" "$MACOS_DIR/Sources/Views/FloatingIndicator.swift" "if state.showsBoomMic"
assert_contains "Boom crab uses fixed frame" "$MACOS_DIR/Sources/Views/FloatingIndicator.swift" 'boomMicFrameNames = \["recording-2"\]'
wall_recording_frame_count="$(
  find "$MACOS_DIR/Resources/CrabSpritesWall" -maxdepth 1 -type f -name 'recording-*.png' | wc -l | tr -d ' '
)"
if [[ -f "$MACOS_DIR/Resources/CrabSpritesWall/recording-2.png" && "$wall_recording_frame_count" == "1" ]]; then
  record_pass "Wall boom resources only include fixed frame"
else
  record_fail "Wall boom resources only include fixed frame"
fi
assert_contains "Boom crab scale matches idle crab" "$MACOS_DIR/Sources/Views/FloatingIndicator.swift" "boomScale"
assert_contains "Crab idle uses ping-pong frame cycle" "$MACOS_DIR/Sources/Views/FloatingIndicator.swift" "pingPongFrameNames\\(prefix: \"idle\""
assert_contains "Crab processing spinner has tuned duration" "$MACOS_DIR/Sources/Views/FloatingIndicator.swift" "processingSpinDuration"
assert_contains "Crab processing spinner rotates continuously" "$MACOS_DIR/Sources/Views/FloatingIndicator.swift" "processingRotation \\+= 360"
assert_contains "Classic overlay has compact layout" "$MACOS_DIR/Sources/Views/FloatingIndicator.swift" "ClassicOverlayLayout"
assert_contains "Crab overlay has visible dark-surface halo" "$MACOS_DIR/Sources/Views/FloatingIndicator.swift" "white.opacity"

if [[ "${SKIP_SWIFTPM:-false}" == "true" ]]; then
  printf 'skip - SwiftPM checks skipped by SKIP_SWIFTPM=true\n'
else
  if run_swift_tests; then
    record_pass "Swift unit tests pass"
  else
    record_fail "Swift unit tests pass"
  fi

  if (cd "$MACOS_DIR" && run_with_speech_analyzer_toolchain swift build); then
    record_pass "Swift package builds"
  else
    record_fail "Swift package builds"
  fi
fi

printf '\n%d passed, %d failed\n' "$pass_count" "$fail_count"
if [[ "$fail_count" -gt 0 ]]; then
  exit 1
fi
