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

assert_not_contains() {
  local name="$1"
  local file="$2"
  local pattern="$3"
  if command -v rg >/dev/null 2>&1; then
    if rg -q "$pattern" "$file"; then
      record_fail "$name"
    else
      record_pass "$name"
    fi
    return
  fi

  if grep -Eq "$pattern" "$file"; then
    record_fail "$name"
  else
    record_pass "$name"
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
assert_not_contains "README does not mention stale source branding" "$REPO_ROOT/README.md" "[Ii]nputalk"
assert_contains "README documents Microphone" "$REPO_ROOT/README.md" "Microphone"
assert_contains "README documents Speech Recognition" "$REPO_ROOT/README.md" "Speech Recognition"
assert_contains "README documents Apple Dictation" "$REPO_ROOT/README.md" "Apple Dictation"
assert_contains "README documents Accessibility" "$REPO_ROOT/README.md" "Accessibility"
assert_contains "README documents Input Monitoring" "$REPO_ROOT/README.md" "Input Monitoring"
assert_contains "README documents pinned Actions install" "$REPO_ROOT/README.md" "SHOUTOUT_RUN_ID"
assert_contains "README links troubleshooting" "$REPO_ROOT/README.md" "TROUBLESHOOTING.md"
assert_contains "README documents context-aware insertion" "$REPO_ROOT/README.md" "focused-field context"
assert_contains "README documents smart spacing fallback" "$REPO_ROOT/README.md" "Smart spacing falls back"
assert_contains "README documents custom shortcuts" "$REPO_ROOT/README.md" "Option Space"
assert_contains "README documents Sparkle key setup" "$REPO_ROOT/README.md" "make sparkle-public-key"
assert_contains "README documents Sparkle appcast" "$REPO_ROOT/README.md" "make sparkle-appcast"
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
assert_contains "Makefile has release preflight target" "$REPO_ROOT/Makefile" "^release-preflight:"
assert_contains "Makefile has Sparkle public key target" "$REPO_ROOT/Makefile" "^sparkle-public-key:"
assert_contains "Makefile has Sparkle appcast target" "$REPO_ROOT/Makefile" "^sparkle-appcast:"
assert_contains "Makefile release DMG passes architecture setting" "$REPO_ROOT/Makefile" 'UNIVERSAL="\$\(UNIVERSAL\)" ./scripts/release.sh'
assert_contains "Makefile has web app check" "$REPO_ROOT/Makefile" "^web-check:"
assert_contains "Makefile has web build target" "$REPO_ROOT/Makefile" "^web-build:"
assert_contains "Makefile restart skips onboarding" "$REPO_ROOT/Makefile" "hasCompletedOnboarding"
assert_contains "Install script downloads CI artifact" "$REPO_ROOT/scripts/install-latest.sh" "gh run download"
assert_contains "Install script uses stable local signing" "$REPO_ROOT/scripts/install-latest.sh" "designated => identifier"
assert_contains "Install script resets stale hotkey permissions" "$REPO_ROOT/scripts/install-latest.sh" "reset_hotkey_permissions_if_existing_install_used_unstable_signature"
assert_contains "Makefile can reset TCC permissions" "$REPO_ROOT/Makefile" "reset-permissions"
assert_contains "Package name is ShoutOut" "$MACOS_DIR/Package.swift" 'name: "ShoutOut"'
assert_contains "Executable target is ShoutOut" "$MACOS_DIR/Package.swift" 'name: "ShoutOut"'
assert_contains "Library target is ShoutOutCore" "$MACOS_DIR/Package.swift" 'name: "ShoutOutCore"'
assert_contains "Test target is ShoutOutCoreTests" "$MACOS_DIR/Package.swift" 'name: "ShoutOutCoreTests"'
assert_contains "Package depends on Sparkle" "$MACOS_DIR/Package.swift" "sparkle-project/Sparkle"
assert_plist_value "Info.plist bundle name is ShoutOut" "$MACOS_DIR/Resources/Info.plist" "CFBundleName" "ShoutOut"
assert_plist_value "Info.plist executable is ShoutOut" "$MACOS_DIR/Resources/Info.plist" "CFBundleExecutable" "ShoutOut"
assert_plist_value "Info.plist bundle id is com.ezraapple.shoutout" "$MACOS_DIR/Resources/Info.plist" "CFBundleIdentifier" "com.ezraapple.shoutout"
assert_plist_key "Info.plist has microphone usage text" "$MACOS_DIR/Resources/Info.plist" "NSMicrophoneUsageDescription"
assert_plist_key "Info.plist has speech recognition usage text" "$MACOS_DIR/Resources/Info.plist" "NSSpeechRecognitionUsageDescription"
assert_plist_key "Info.plist has accessibility usage text" "$MACOS_DIR/Resources/Info.plist" "NSAccessibilityUsageDescription"
assert_plist_key "Info.plist has input monitoring usage text" "$MACOS_DIR/Resources/Info.plist" "NSInputMonitoringUsageDescription"
assert_plist_key "Info.plist has Sparkle feed URL" "$MACOS_DIR/Resources/Info.plist" "SUFeedURL"
assert_plist_key "Info.plist has Sparkle public key slot" "$MACOS_DIR/Resources/Info.plist" "SUPublicEDKey"
assert_contains "Entitlements allow audio input" "$MACOS_DIR/Resources/ShoutOut.entitlements" "com.apple.security.device.audio-input"
assert_contains "Build script builds ShoutOut.app" "$MACOS_DIR/scripts/build-app.sh" 'APP_NAME="ShoutOut"'
assert_contains "Build script has executable name" "$MACOS_DIR/scripts/build-app.sh" 'EXECUTABLE_NAME="ShoutOut"'
assert_contains "Build script signs for local use" "$MACOS_DIR/scripts/build-app.sh" "Ad-hoc signing"
assert_contains "Build script uses stable local signing" "$MACOS_DIR/scripts/build-app.sh" "designated => identifier"
assert_contains "Build script auto-selects current CLT" "$MACOS_DIR/scripts/build-app.sh" "Command Line Tools for Apple Dictation support"
assert_contains "Build script copies app icon variants" "$MACOS_DIR/scripts/build-app.sh" "AppIconVariants"
assert_contains "Build script copies tinted crab variants" "$MACOS_DIR/scripts/build-app.sh" "CrabSpriteVariants"
assert_contains "Build script copies tinted wall crab variants" "$MACOS_DIR/scripts/build-app.sh" "CrabSpriteWallVariants"
assert_contains "Build script stamps git commit" "$MACOS_DIR/scripts/build-app.sh" "ShoutOutGitCommit"
assert_contains "Build script stamps build time" "$MACOS_DIR/scripts/build-app.sh" "ShoutOutBuiltAt"
assert_contains "Build script copies Sparkle framework" "$MACOS_DIR/scripts/build-app.sh" "Contents/Frameworks"
assert_contains "Build script adds framework rpath" "$MACOS_DIR/scripts/build-app.sh" "@executable_path/../Frameworks"
assert_contains "Build script signs Sparkle nested code" "$MACOS_DIR/scripts/build-app.sh" "sign_framework_inside_out"
assert_contains "Build script injects Sparkle public key" "$MACOS_DIR/scripts/build-app.sh" "SPARKLE_PUBLIC_ED_KEY"
assert_contains "Release script creates DMG" "$MACOS_DIR/scripts/release.sh" "create-dmg.sh"
assert_contains "Release preflight checks Developer ID" "$MACOS_DIR/scripts/release-preflight.sh" "Developer ID Application"
assert_contains "Release preflight checks notary profile" "$MACOS_DIR/scripts/release-preflight.sh" "notarytool history"
assert_contains "Release preflight checks Sparkle public key" "$MACOS_DIR/scripts/release-preflight.sh" "SPARKLE_PUBLIC_ED_KEY"
assert_contains "DMG script supports notarization profile" "$MACOS_DIR/scripts/create-dmg.sh" "NOTARY_PROFILE"
assert_contains "DMG script uses built-in hdiutil" "$MACOS_DIR/scripts/create-dmg.sh" "hdiutil create"
assert_contains "Sparkle key script uses generate_keys" "$MACOS_DIR/scripts/sparkle-public-key.sh" "generate_keys"
assert_contains "Sparkle appcast script uses generate_appcast" "$MACOS_DIR/scripts/generate-appcast.sh" "generate_appcast"
assert_contains "Sparkle appcast stages web appcast" "$MACOS_DIR/scripts/generate-appcast.sh" "apps/web/public"
assert_contains "Sparkle appcast stages releases directory" "$MACOS_DIR/scripts/generate-appcast.sh" "WEB_PUBLIC_DIR/releases"
assert_contains "Sparkle appcast stages release notes" "$MACOS_DIR/scripts/generate-appcast.sh" "RELEASE_NOTES_URL_PREFIX"
assert_contains "Web Vite package exists" "$REPO_ROOT/apps/web/package.json" '"vite"'
assert_contains "Web Vercel config exists" "$REPO_ROOT/apps/web/vercel.json" '"framework": "vite"'
assert_contains "Web landing page names ShoutOut" "$REPO_ROOT/apps/web/index.html" "ShoutOut"
assert_contains "Web landing page explains permissions" "$REPO_ROOT/apps/web/index.html" "Input Monitoring"
assert_contains "Web landing page has Open Graph title" "$REPO_ROOT/apps/web/index.html" 'property="og:title" content="ShoutOut"'
assert_contains "Web landing page has Open Graph description" "$REPO_ROOT/apps/web/index.html" 'property="og:description"'
assert_contains "Web landing page has Open Graph image" "$REPO_ROOT/apps/web/index.html" 'property="og:image" content="https://shoutout.sh/assets/pixel-hero.png"'
assert_contains "Web landing page has large Twitter preview card" "$REPO_ROOT/apps/web/index.html" 'name="twitter:card" content="summary_large_image"'
assert_contains "Web download function is self-contained for Vercel project root" "$REPO_ROOT/apps/web/api/download.js" "DEFAULT_RELEASE_VERSION"
assert_contains "Test script auto-selects current CLT" "$REPO_ROOT/scripts/test.sh" "Command Line Tools for Apple Dictation support"
assert_contains "Transcription imports core" "$MACOS_DIR/Sources/Services/TranscriptionService.swift" "import ShoutOutCore"
assert_contains "Transcription returns result shape" "$MACOS_DIR/Sources/Services/TranscriptionService.swift" "DictationResult"
assert_contains "Transcription records timing snapshot" "$MACOS_DIR/Sources/Services/TranscriptionService.swift" "TranscriptionTimingSnapshot"
assert_contains "Transcription supports backend selection" "$MACOS_DIR/Sources/Services/TranscriptionService.swift" "selectedBackend"
assert_contains "Transcription defaults to WhisperKit" "$MACOS_DIR/Sources/Services/TranscriptionService.swift" "\\?\\? \\.whisperKit"
assert_contains "Transcription has swappable engine protocol" "$MACOS_DIR/Sources/Services/TranscriptionBackend.swift" "protocol TranscriptionEngine"
assert_contains "Transcription exposes Apple Dictation backend" "$MACOS_DIR/Sources/Services/TranscriptionBackend.swift" "appleDictation"
assert_contains "Transcription auto-routes long Apple sessions" "$MACOS_DIR/Sources/Services/TranscriptionService.swift" "transcription autoswitch backend=appleDictation"
assert_contains "Transcription restores Apple Speech readiness after long load failure" "$MACOS_DIR/Sources/Services/TranscriptionService.swift" "modelState = \\.ready"
assert_contains "WhisperKit is behind an engine" "$MACOS_DIR/Sources/Services/WhisperKitTranscriptionEngine.swift" "WhisperKitTranscriptionEngine"
assert_contains "Apple Speech backend requires on-device recognition" "$MACOS_DIR/Sources/Services/AppleSpeechTranscriptionEngine.swift" "requiresOnDeviceRecognition = true"
assert_contains "Apple Dictation backend uses SpeechAnalyzer" "$MACOS_DIR/Sources/Services/AppleDictationTranscriptionEngine.swift" "SpeechAnalyzer"
assert_contains "Apple Dictation backend uses range reconciliation" "$MACOS_DIR/Sources/Services/AppleDictationTranscriptionEngine.swift" "TimeRangeTranscript"
assert_contains "Settings expose insights" "$MACOS_DIR/Sources/Views/SettingsView.swift" "Insights"
assert_contains "Settings expose audio ducking" "$MACOS_DIR/Sources/Views/SettingsView.swift" "Dim system audio"
assert_contains "Settings expose indicator picker" "$MACOS_DIR/Sources/Views/SettingsView.swift" "Indicator"
assert_contains "Settings expose crab color picker" "$MACOS_DIR/Sources/Views/SettingsView.swift" "Crab Color"
assert_contains "Settings expose shortcut picker" "$MACOS_DIR/Sources/Views/SettingsView.swift" "HotkeyTrigger.allCases"
assert_contains "Settings expose boring mode" "$MACOS_DIR/Sources/Views/SettingsView.swift" "Boring mode"
assert_not_contains "Settings do not expose dictionary" "$MACOS_DIR/Sources/Views/SettingsView.swift" "DictionarySettingsView"
assert_contains "Settings expose engine picker" "$MACOS_DIR/Sources/Views/SettingsView.swift" "Engine"
assert_contains "Settings explain engine quality and speed" "$MACOS_DIR/Sources/Views/SettingsView.swift" "EngineGuideRow"
assert_contains "Settings expose smart spacing toggle" "$MACOS_DIR/Sources/Views/SettingsView.swift" "Smart spacing"
assert_contains "Settings expose trailing space fallback toggle" "$MACOS_DIR/Sources/Views/SettingsView.swift" "Fallback trailing space"
assert_not_contains "Settings hide semantic rewrite toggle" "$MACOS_DIR/Sources/Views/SettingsView.swift" "Rewrite self-corrections"
assert_contains "Settings expose cleanup timing text" "$MACOS_DIR/Sources/Views/SettingsView.swift" "Last cleanup"
assert_contains "Settings expose model progress bar" "$MACOS_DIR/Sources/Views/SettingsView.swift" "ModelProgressBar"
assert_contains "Settings expose diagnostics export" "$MACOS_DIR/Sources/Views/SettingsView.swift" "Export Diagnostics"
assert_contains "Settings expose app version helper" "$MACOS_DIR/Sources/Views/SettingsView.swift" "AppVersionInfo.displayWithCommit"
assert_contains "Settings expose update status" "$MACOS_DIR/Sources/Views/SettingsView.swift" "AppUpdaterConfiguration.statusText"
assert_contains "Settings confirms stats deletion" "$MACOS_DIR/Sources/Views/SettingsView.swift" "Clear local stats\\?"
assert_contains "Home window has dashboard surface" "$MACOS_DIR/Sources/Views/ShoutOutHomeView.swift" "ShoutOutHomeView"
assert_contains "Home window exposes settings page" "$MACOS_DIR/Sources/Views/ShoutOutHomeView.swift" "case settings"
assert_contains "Home window exposes shortcut picker" "$MACOS_DIR/Sources/Views/ShoutOutHomeView.swift" "HotkeyTrigger.allCases"
assert_contains "Home window exposes diagnostics export" "$MACOS_DIR/Sources/Views/ShoutOutHomeView.swift" "Diagnostics"
assert_contains "Home window exposes app version helper" "$MACOS_DIR/Sources/Views/ShoutOutHomeView.swift" "AppVersionInfo.displayWithCommit"
assert_contains "Diagnostics exporter avoids transcript data" "$MACOS_DIR/Sources/Services/DiagnosticsExporter.swift" "clipboard contents"
assert_contains "Diagnostics exporter copies runtime log" "$MACOS_DIR/Sources/Services/DiagnosticsExporter.swift" "RuntimeLog.logURL"
assert_contains "Diagnostics exporter sanitizes legacy language pass text" "$MACOS_DIR/Sources/Services/DiagnosticsExporter.swift" "sanitizeLegacyLanguagePassFields"
assert_contains "Diagnostics exporter collects crash reports" "$MACOS_DIR/Sources/Services/DiagnosticsExporter.swift" "DiagnosticReports"
assert_contains "Diagnostics exporter records updater state" "$MACOS_DIR/Sources/Services/DiagnosticsExporter.swift" "updaterConfigured"
assert_contains "App launch logs version" "$MACOS_DIR/Sources/AppDelegate.swift" "AppVersionInfo.version"
assert_contains "App delegate wires Sparkle updater" "$MACOS_DIR/Sources/AppDelegate.swift" "SPUStandardUpdaterController"
assert_contains "App updater stays disabled without public key" "$MACOS_DIR/Sources/Services/AppUpdaterConfiguration.swift" "placeholderPublicKey"
assert_contains "Home window exposes boring mode" "$MACOS_DIR/Sources/Views/ShoutOutHomeView.swift" "Boring mode"
assert_contains "Home window confirms stats deletion" "$MACOS_DIR/Sources/Views/ShoutOutHomeView.swift" "Clear local stats\\?"
assert_contains "Home menus highlight hovered rows" "$MACOS_DIR/Sources/Views/ShoutOutHomeView.swift" "onHover"
assert_contains "Home brand mark uses colored crab" "$MACOS_DIR/Sources/Views/ShoutOutHomeView.swift" "crabColorVariant"
assert_contains "Home brand mark uses tinted crab variants" "$MACOS_DIR/Sources/Views/ShoutOutHomeView.swift" "CrabSpriteVariants"
assert_contains "Home crab color menu previews colors" "$MACOS_DIR/Sources/Views/ShoutOutHomeView.swift" "ColorPreviewTile"
assert_not_contains "Home window does not expose dictionary panel" "$MACOS_DIR/Sources/Views/ShoutOutHomeView.swift" "HomeDictionaryPanel"
assert_contains "Model picker uses plain-English choices" "$MACOS_DIR/Sources/Services/TranscriptionModelOption.swift" "Large v3 Turbo"
assert_contains "Model picker exposes benchmark turbo candidate" "$MACOS_DIR/Sources/Services/TranscriptionModelOption.swift" "large-v3-v20240930_turbo_632MB"
assert_contains "Settings model picker is advanced-only" "$MACOS_DIR/Sources/Views/SettingsView.swift" "TranscriptionModelOption\\.advancedOptions"
assert_contains "Settings describes transcription model differences" "$MACOS_DIR/Sources/Views/SettingsView.swift" "TranscriptionModelOption\\.advancedComparisonText"
assert_contains "App delegate keeps app alive after closing windows" "$MACOS_DIR/Sources/AppDelegate.swift" "applicationShouldTerminateAfterLastWindowClosed"
assert_contains "App delegate reopens home from Dock" "$MACOS_DIR/Sources/AppDelegate.swift" "applicationShouldHandleReopen"
assert_contains "Onboarding exposes model progress bar" "$MACOS_DIR/Sources/Views/OnboardingView.swift" "ModelProgressBar"
assert_contains "Onboarding exposes Speech Recognition permission" "$MACOS_DIR/Sources/Views/OnboardingView.swift" "Speech Recognition"
assert_contains "Model state exposes startup progress" "$MACOS_DIR/Sources/Services/TranscriptionService.swift" "startupProgress"
assert_contains "Usage stats persist performance metrics" "$MACOS_DIR/Sources/Core/UsageStatsStore.swift" "UsagePerformanceMetrics"
assert_contains "Permission manager checks input monitoring" "$MACOS_DIR/Sources/Services/PermissionManager.swift" "CGPreflightListenEventAccess"
assert_contains "Permission manager checks speech recognition" "$MACOS_DIR/Sources/Services/PermissionManager.swift" "SpeechAuthorization.currentStatus"
assert_contains "Speech authorization wraps SFSpeechRecognizer status" "$MACOS_DIR/Sources/Services/SpeechAuthorization.swift" "SFSpeechRecognizer.authorizationStatus"
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
assert_contains "Core uses context window for insertion casing" "$MACOS_DIR/Sources/Core/TextInsertionFormatter.swift" "textBefore"
assert_contains "WhisperKit cleans interrupted downloads" "$MACOS_DIR/Sources/Services/WhisperKitTranscriptionEngine.swift" "cleanupInterruptedDownloads"
assert_contains "WhisperKit removes transient extraction dirs" "$MACOS_DIR/Sources/Services/WhisperKitTranscriptionEngine.swift" ".extracting"
assert_not_contains "Postprocessor has no hardcoded self-correction cleanup" "$MACOS_DIR/Sources/Core/TextPostProcessor.swift" "cleanUpSelfCorrections"
assert_contains "Hotkey starts capture immediately" "$MACOS_DIR/Sources/Services/HotkeyManager.swift" "start audio capture immediately"
assert_contains "Hotkey captures event timestamp before main dispatch" "$MACOS_DIR/Sources/Services/HotkeyManager.swift" "eventTimestamp = CFAbsoluteTimeGetCurrent"
assert_contains "Hotkey commits delayed holds by timestamp" "$MACOS_DIR/Sources/Core/ShortcutTimingStateMachine.swift" "heldDuration >= holdThreshold"
assert_contains "Hotkey supports configurable triggers" "$MACOS_DIR/Sources/Services/HotkeyTrigger.swift" "optionSpace"
assert_contains "App delegate tracks committed recordings" "$MACOS_DIR/Sources/AppDelegate.swift" "recordingIsCommitted"
assert_contains "App delegate discards quick releases" "$MACOS_DIR/Sources/AppDelegate.swift" "quickRelease"
assert_contains "Audio recorder allows fast snippets" "$MACOS_DIR/Sources/Services/AudioRecorder.swift" "minimumSamples = 3200"
assert_contains "Audio recorder logs input format" "$MACOS_DIR/Sources/Services/AudioRecorder.swift" "record input format"
assert_contains "Audio converter provides each tap buffer once" "$MACOS_DIR/Sources/Services/AudioConverterInputProvider.swift" "didProvideInput"
assert_contains "Audio signal analysis gates silence" "$MACOS_DIR/Sources/Core/AudioSignalAnalysis.swift" "hasSpeechLikeAudio"
assert_contains "App delegate blocks silent recordings" "$MACOS_DIR/Sources/AppDelegate.swift" "record stopped silent"
assert_contains "App delegate treats silent recordings as idle" "$MACOS_DIR/Sources/AppDelegate.swift" "finishIndicator()"
assert_contains "App delegate starts independent transcription sessions" "$MACOS_DIR/Sources/AppDelegate.swift" "latestTranscriptionSessionID"
assert_contains "App delegate drops stale transcription sessions" "$MACOS_DIR/Sources/AppDelegate.swift" "transcription stale"
assert_contains "App delegate tracks pending transcriptions" "$MACOS_DIR/Sources/AppDelegate.swift" "pendingTranscriptionCount"
assert_contains "App delegate records usage stats" "$MACOS_DIR/Sources/AppDelegate.swift" "usageStats"
assert_contains "App delegate ducks audio" "$MACOS_DIR/Sources/AppDelegate.swift" "audioDucker"
assert_contains "App delegate applies selected app icon variant" "$MACOS_DIR/Sources/AppDelegate.swift" "applyApplicationIconVariant"
assert_contains "App delegate defaults to crab overlay" "$MACOS_DIR/Sources/AppDelegate.swift" "OverlayStyle.crab"
assert_contains "App delegate lets boring mode force classic overlay" "$MACOS_DIR/Sources/AppDelegate.swift" "Defaults.boringMode"
assert_contains "App delegate keeps overlay above apps" "$MACOS_DIR/Sources/AppDelegate.swift" "panel.level = .statusBar"
assert_contains "App delegate supports overlay preview mode" "$MACOS_DIR/Sources/AppDelegate.swift" "SHOUTOUT_OVERLAY_PREVIEW"
assert_contains "App delegate creates overlay with concrete frame" "$MACOS_DIR/Sources/AppDelegate.swift" "initialIndicatorFrame"
assert_contains "App delegate logs preview overlay visibility" "$MACOS_DIR/Sources/AppDelegate.swift" "shoutout-overlay-preview.log"
assert_contains "App delegate can snapshot overlay previews" "$MACOS_DIR/Sources/AppDelegate.swift" "SHOUTOUT_OVERLAY_SNAPSHOT_PATH"
assert_contains "Crab overlay has boom mic" "$MACOS_DIR/Sources/Views/FloatingIndicator.swift" "boomMic"
assert_contains "Crab overlay shows processing badge" "$MACOS_DIR/Sources/Views/FloatingIndicator.swift" "processingBadge"
assert_contains "Crab overlay animates wall crab" "$MACOS_DIR/Sources/Views/FloatingIndicator.swift" "animateCrab"
assert_contains "Crab overlay supports color variants" "$MACOS_DIR/Sources/Views/FloatingIndicator.swift" "CrabColorVariant"
assert_contains "Crab overlay uses tinted wall variants" "$MACOS_DIR/Sources/Views/FloatingIndicator.swift" "CrabSpriteWallVariants"
assert_contains "Mascot sync generates app icon variants" "$REPO_ROOT/scripts/sync-mascot-assets.py" "write_app_icon_variants"
assert_contains "App icon variants share crab color transform" "$REPO_ROOT/scripts/sync-mascot-assets.py" '"gold": \(-128, 1, 0\)'
assert_contains "Mascot sync includes original black crab" "$REPO_ROOT/scripts/sync-mascot-assets.py" '"black": \(0, 0.20, -0.42\)'
assert_not_contains "App icon variants avoid flat target-color replacement" "$REPO_ROOT/scripts/sync-mascot-assets.py" "target_rgb"
assert_contains "Mascot sync generates tinted crab variants" "$REPO_ROOT/scripts/sync-mascot-assets.py" "write_tinted_sprite_variants"
tinted_crab_variant_count="$(
  find "$MACOS_DIR/Resources/CrabSpriteVariants" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' '
)"
tinted_wall_variant_count="$(
  find "$MACOS_DIR/Resources/CrabSpriteWallVariants" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' '
)"
if [[ "$tinted_crab_variant_count" -ge 21 && "$tinted_wall_variant_count" -ge 21 ]]; then
  record_pass "Tinted crab variants are prebuilt"
else
  record_fail "Tinted crab variants are prebuilt"
fi
app_icon_variant_count="$(
  find "$MACOS_DIR/Resources/AppIconVariants" -maxdepth 1 -type f -name '*.png' 2>/dev/null | wc -l | tr -d ' '
)"
if [[ "$app_icon_variant_count" -ge 21 ]]; then
  record_pass "App icon variants are prebuilt"
else
  record_fail "App icon variants are prebuilt"
fi
if [[ -f "$MACOS_DIR/Resources/CrabSpriteVariants/black/idle-1.png" && -f "$MACOS_DIR/Resources/AppIconVariants/black.png" ]]; then
  record_pass "Original black crab assets are prebuilt"
else
  record_fail "Original black crab assets are prebuilt"
fi
if python3 - "$MACOS_DIR/Resources/AppIconVariants" <<'PY'
from pathlib import Path
from PIL import Image
import sys

variants = sorted(Path(sys.argv[1]).glob("*.png"))
if len(variants) < 20:
    raise SystemExit(1)
for path in variants:
    image = Image.open(path).convert("RGBA")
    if image.getpixel((0, 0))[3] != 0:
        raise SystemExit(f"{path.name} has an opaque corner")
    bbox = image.getchannel("A").getbbox()
    if bbox is None or bbox == (0, 0, image.width, image.height):
        raise SystemExit(f"{path.name} is not a transparent cutout")
PY
then
  record_pass "App icon variants are transparent cutouts"
else
  record_fail "App icon variants are transparent cutouts"
fi
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
if python3 - "$REPO_ROOT" <<'PY'
from pathlib import Path
from PIL import Image
import sys

root = Path(sys.argv[1])
idle = Image.open(root / "assets/mascot/idle-walk/frame-1.png").convert("RGBA")
overlay = Image.open(root / "assets/mascot/recording-boom/boom-mic-overlay.png").convert("RGBA")
recording = Image.open(root / "assets/mascot/recording-boom/frame-1.png").convert("RGBA")
expected = idle.copy()
expected.alpha_composite(overlay)
if list(expected.getdata()) != list(recording.getdata()):
    raise SystemExit(1)
PY
then
  record_pass "Recording mascot is idle plus boom overlay"
else
  record_fail "Recording mascot is idle plus boom overlay"
fi
if python3 - "$REPO_ROOT" <<'PY'
import importlib.util
from pathlib import Path
from PIL import Image
import sys

root = Path(sys.argv[1])
sync_script = root / "scripts/sync-mascot-assets.py"
spec = importlib.util.spec_from_file_location("sync_mascot_assets", sync_script)
sync_mascot_assets = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sync_mascot_assets)

idle = Image.open(root / "assets/mascot/idle-walk/frame-1.png").convert("RGBA")
idle_wall = sync_mascot_assets.fit_on_canvas(
    idle,
    sync_mascot_assets.WALL_IDLE_CANVAS_SIZE,
    padding=4,
    rotation_degrees=90,
    trailing_bleed_pixels=5,
)
expected = Image.new("RGBA", sync_mascot_assets.WALL_RECORDING_CANVAS_SIZE, (0, 0, 0, 0))
vertical_offset = (
    sync_mascot_assets.WALL_RECORDING_CANVAS_SIZE[1]
    - sync_mascot_assets.WALL_IDLE_CANVAS_SIZE[1]
) // 2
expected.alpha_composite(idle_wall, (0, vertical_offset))
overlay_canvas = Image.new("RGBA", sync_mascot_assets.WALL_RECORDING_CANVAS_SIZE, (0, 0, 0, 0))
overlay_canvas.alpha_composite(sync_mascot_assets.compose_wall_boom_overlay())
if any(overlay_canvas.getpixel((x, overlay_canvas.height - 1))[3] for x in range(overlay_canvas.width)):
    raise SystemExit(1)
expected.alpha_composite(
    overlay_canvas
)
recording_wall = Image.open(
    root / "apps/macos/Resources/CrabSpritesWall/idle-1.png"
).convert("RGBA")
if idle_wall.size != recording_wall.size:
    raise SystemExit(1)
if list(idle_wall.getdata()) != list(recording_wall.getdata()):
    raise SystemExit(1)
actual = Image.open(
    root / "apps/macos/Resources/CrabSpritesWall/recording-2.png"
).convert("RGBA")
if actual.size != expected.size or actual.height <= recording_wall.height:
    raise SystemExit(1)
if list(expected.getdata()) != list(actual.getdata()):
    raise SystemExit(1)
PY
then
  record_pass "Wall boom is idle plus transformed overlay"
else
  record_fail "Wall boom is idle plus transformed overlay"
fi
assert_contains "Boom crab scale matches idle crab" "$MACOS_DIR/Sources/Views/FloatingIndicator.swift" "boomScale"
assert_contains "Crab idle uses ping-pong frame cycle" "$MACOS_DIR/Sources/Views/FloatingIndicator.swift" "pingPongFrameNames\\(prefix: \"idle\""
assert_contains "Crab processing spinner has tuned duration" "$MACOS_DIR/Sources/Views/FloatingIndicator.swift" "processingSpinDuration"
assert_contains "Crab processing spinner rotates continuously" "$MACOS_DIR/Sources/Views/FloatingIndicator.swift" "processingRotation \\+= 360"
assert_contains "Classic overlay has compact layout" "$MACOS_DIR/Sources/Views/FloatingIndicator.swift" "ClassicOverlayLayout"
assert_contains "Classic overlay has idle nub" "$MACOS_DIR/Sources/Views/FloatingIndicator.swift" "CGSize\\(width: 14, height: 44\\)"
assert_contains "Classic overlay responds to audio level" "$MACOS_DIR/Sources/Views/FloatingIndicator.swift" "recordingBarWidth"
assert_contains "Classic overlay sits on right edge" "$MACOS_DIR/Sources/AppDelegate.swift" "positionClassicAtScreenRight"
assert_contains "Classic overlay keeps persistent host for morphs" "$MACOS_DIR/Sources/AppDelegate.swift" "indicatorOverlayModel\\?\\.update"
assert_contains "Classic overlay has hands-free controls" "$MACOS_DIR/Sources/Views/FloatingIndicator.swift" "overlayActionButton"
assert_contains "Classic hands-free controls receive clicks" "$MACOS_DIR/Sources/AppDelegate.swift" "shouldIgnoreIndicatorMouseEvents"
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
