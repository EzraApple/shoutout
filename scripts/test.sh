#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="${SHOUTOUT_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
MACOS_DIR="$REPO_ROOT/apps/macos"
PYTHON_BIN="${PYTHON_BIN:-${PYTHON:-python3}}"
export PYTHONDONTWRITEBYTECODE="${PYTHONDONTWRITEBYTECODE:-1}"

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

assert_path_missing() {
  local name="$1"
  local path="$2"
  if [[ ! -e "$path" ]]; then
    record_pass "$name"
  else
    record_fail "$name"
  fi
}

assert_contains "README names ShoutOut" "$REPO_ROOT/README.md" "^# ShoutOut"
assert_contains "README describes local-first dictation" "$REPO_ROOT/README.md" "local-first macOS dictation"
assert_contains "README documents current crab art" "$REPO_ROOT/README.md" "boom-mic recording animation"
assert_contains "README documents mascot asset sync" "$REPO_ROOT/README.md" "scripts/sync-mascot-assets.py"
assert_contains "README documents release prep scripts" "$REPO_ROOT/README.md" "make release-preflight"
assert_not_contains "README avoids public download framing" "$REPO_ROOT/README.md" "^## Download$|git clone|Download the signed Mac app"
assert_not_contains "README avoids settled open-source license claim" "$REPO_ROOT/README.md" "released under the MIT license|MIT license"
assert_contains "README documents no source license grant" "$REPO_ROOT/README.md" "No open-source license is granted"
assert_path_missing "LICENSE file is intentionally absent" "$REPO_ROOT/LICENSE"
assert_not_contains "README does not mention stale source branding" "$REPO_ROOT/README.md" "[Ii]nputalk"
assert_contains "README documents Microphone" "$REPO_ROOT/README.md" "Microphone"
assert_contains "README documents Speech Recognition" "$REPO_ROOT/README.md" "Speech Recognition"
assert_contains "README documents Apple Dictation" "$REPO_ROOT/README.md" "Apple Dictation"
assert_contains "README documents Accessibility" "$REPO_ROOT/README.md" "Accessibility"
assert_contains "README documents Input Monitoring" "$REPO_ROOT/README.md" "Input Monitoring"
assert_not_contains "README avoids GitHub Actions install guidance" "$REPO_ROOT/README.md" "SHOUTOUT_RUN_ID|GitHub Actions"
assert_contains "README links troubleshooting" "$REPO_ROOT/README.md" "TROUBLESHOOTING.md"
assert_contains "README documents context-aware insertion" "$REPO_ROOT/README.md" "focused-field context"
assert_contains "README documents smart spacing fallback" "$REPO_ROOT/README.md" "falls back safely"
assert_contains "README documents custom shortcuts" "$REPO_ROOT/README.md" "Option Space"
assert_contains "README documents Sparkle key setup" "$REPO_ROOT/README.md" "make sparkle-public-key"
assert_contains "README documents Sparkle appcast" "$REPO_ROOT/README.md" "make sparkle-appcast"
assert_contains "Web landing page can describe app as free" "$REPO_ROOT/apps/web/index.html" "free Mac utility"
assert_not_contains "Web landing page avoids open-source claims" "$REPO_ROOT/apps/web/index.html" "open[- ]source|MIT license"
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
assert_not_contains "DMG does not link whole-Mac Applications folder" "$MACOS_DIR/scripts/create-dmg.sh" "ln -s /Applications"
assert_not_contains "DMG background avoids drag-to-Applications arrow" "$MACOS_DIR/scripts/render-dmg-background.swift" "arrowHead|applicationsPanel"
assert_contains "App delegate relocates before onboarding" "$MACOS_DIR/Sources/AppDelegate.swift" "AppRelocator.installToUserApplicationsIfNeeded"
assert_contains "App relocator targets user Applications" "$MACOS_DIR/Sources/Services/AppRelocator.swift" "userApplicationsDirectory"
assert_contains "App relocator uses user domain" "$MACOS_DIR/Sources/Services/AppRelocator.swift" "userDomainMask"
assert_contains "App relocator handles root Applications as source only" "$MACOS_DIR/Sources/Services/AppRelocator.swift" "rootApplications"
assert_contains "App relocator relaunches installed copy as new instance" "$MACOS_DIR/Sources/Services/AppRelocator.swift" '"-n"'
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
assert_contains "Settings cleanup summary uses display copy" "$MACOS_DIR/Sources/Views/SettingsView.swift" "LanguagePassDisplayCopy\\.summary"
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
assert_contains "Status menu uses square popover panel" "$MACOS_DIR/Sources/AppDelegate.swift" "SharpPopoverPanel"
assert_contains "Status popover disables rounded host corners" "$MACOS_DIR/Sources/AppDelegate.swift" "cornerRadius = 0"
assert_not_contains "Status menu avoids rounded NSMenu popover" "$MACOS_DIR/Sources/AppDelegate.swift" "showContextMenu"
assert_contains "Home window exposes boring mode" "$MACOS_DIR/Sources/Views/ShoutOutHomeView.swift" "Boring mode"
assert_contains "Home window confirms stats deletion" "$MACOS_DIR/Sources/Views/ShoutOutHomeView.swift" "Clear local stats\\?"
assert_contains "Home menus highlight hovered rows" "$MACOS_DIR/Sources/Views/ShoutOutHomeView.swift" "onHover"
assert_contains "Home settings toggles use stable app-drawn switch" "$MACOS_DIR/Sources/Views/ShoutOutHomeView.swift" "HomePixelToggleStyle"
assert_contains "Home settings toggles keep binding-based switch state" "$MACOS_DIR/Sources/Views/ShoutOutHomeView.swift" "configuration\\.isOn"
assert_not_contains "Home settings toggles avoid inactive system switch tint" "$MACOS_DIR/Sources/Views/ShoutOutHomeView.swift" "\\.toggleStyle\\(\\.switch\\)"
assert_contains "Home history cleanup summary uses display copy" "$MACOS_DIR/Sources/Views/ShoutOutHomeView.swift" "LanguagePassDisplayCopy\\.status"
assert_contains "Home history cleanup details include compact reason" "$MACOS_DIR/Sources/Views/ShoutOutHomeView.swift" "cleanupTraceRow\\(title: \"Reason\""
assert_contains "Home history cleanup details include selected tone" "$MACOS_DIR/Sources/Views/ShoutOutHomeView.swift" "cleanupTraceRow\\(title: \"Tone\""
assert_not_contains "Home history avoids raw cleanup fallback slugs" "$MACOS_DIR/Sources/Views/ShoutOutHomeView.swift" "languagePassFallbackReason \\?\\? "
assert_contains "Language cleanup dropped-content copy is friendly" "$MACOS_DIR/Sources/Core/LanguagePassDisplayCopy.swift" "No cleanup necessary"
assert_contains "Language cleanup reason copy is compact" "$MACOS_DIR/Sources/Core/LanguagePassDisplayCopy.swift" "Meaning preserved · Tone applied"
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
assert_contains "App delegate drops low-information transcripts" "$MACOS_DIR/Sources/AppDelegate.swift" "TranscriptHallucinationFilter.shouldDrop"
assert_contains "Core drops punctuation-only transcripts" "$MACOS_DIR/Sources/Core/TranscriptHallucinationFilter.swift" "alphanumericCharacterCount == 0"
assert_contains "Core gates low-information transcripts by audio energy" "$MACOS_DIR/Sources/Core/TranscriptHallucinationFilter.swift" "lowEnergyPeak"
assert_not_contains "Core hallucination filter avoids phrase denylist" "$MACOS_DIR/Sources/Core/TranscriptHallucinationFilter.swift" "thank you"
if "$PYTHON_BIN" - "$MACOS_DIR/Sources/AppDelegate.swift" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text()
if "No speech" in source:
    raise SystemExit("empty transcription still shows a no-speech attention badge")

marker = 'RuntimeLog.write("transcription empty")'
index = source.find(marker)
if index == -1:
    raise SystemExit("empty transcription log marker missing")
window = source[index:index + 180]
if "finishIndicator()" not in window:
    raise SystemExit("empty transcription does not finish back to idle")
PY
then
  record_pass "App delegate treats empty transcription as idle"
else
  record_fail "App delegate treats empty transcription as idle"
fi
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
assert_contains "App delegate lets crab tips bleed past screen edge" "$MACOS_DIR/Sources/AppDelegate.swift" "CrabOverlayLayout.screenBleed"
assert_contains "App delegate raises crab above center" "$MACOS_DIR/Sources/AppDelegate.swift" "CrabOverlayLayout.verticalOffset"
assert_contains "App delegate logs preview overlay visibility" "$MACOS_DIR/Sources/AppDelegate.swift" "shoutout-overlay-preview.log"
assert_contains "App delegate can snapshot overlay previews" "$MACOS_DIR/Sources/AppDelegate.swift" "SHOUTOUT_OVERLAY_SNAPSHOT_PATH"
assert_contains "Crab overlay has boom mic" "$MACOS_DIR/Sources/Views/FloatingIndicator.swift" "boomHoldFrameName"
assert_contains "Crab overlay shows processing badge" "$MACOS_DIR/Sources/Views/FloatingIndicator.swift" "processingBadge"
assert_contains "Crab overlay animates wall crab" "$MACOS_DIR/Sources/Views/FloatingIndicator.swift" "animateCrab"
assert_contains "Crab overlay defines edge bleed" "$MACOS_DIR/Sources/Views/FloatingIndicator.swift" "screenBleed"
assert_contains "Crab overlay defines vertical offset" "$MACOS_DIR/Sources/Views/FloatingIndicator.swift" "verticalOffset"
assert_contains "Crab overlay supports color variants" "$MACOS_DIR/Sources/Views/FloatingIndicator.swift" "CrabColorVariant"
assert_contains "Crab overlay uses tinted wall variants" "$MACOS_DIR/Sources/Views/FloatingIndicator.swift" "CrabSpriteWallVariants"
assert_contains "Mascot sync generates app icon variants" "$REPO_ROOT/scripts/sync-mascot-assets.py" "write_app_icon_variants"
assert_contains "Mascot sync writes default app icon fallback" "$REPO_ROOT/scripts/sync-mascot-assets.py" "write_default_app_icon"
assert_contains "App icon variants share crab color transform" "$REPO_ROOT/scripts/sync-mascot-assets.py" '"gold": \(-128, 1, 0\)'
assert_contains "Mascot sync includes readable black crab" "$REPO_ROOT/scripts/sync-mascot-assets.py" '"black": \(0, 0.18, -0.30\)'
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
if "$PYTHON_BIN" - "$MACOS_DIR/Resources/AppIconVariants" <<'PY'
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
if "$PYTHON_BIN" - "$MACOS_DIR/Resources" <<'PY'
from pathlib import Path
from PIL import Image
import subprocess
import sys
import tempfile

resources = Path(sys.argv[1])
with tempfile.TemporaryDirectory() as temporary_directory:
    iconset_path = Path(temporary_directory) / "AppIcon.iconset"
    subprocess.run(
        [
            "iconutil",
            "-c",
            "iconset",
            "-o",
            str(iconset_path),
            str(resources / "AppIcon.icns"),
        ],
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    fallback = Image.open(iconset_path / "icon_512x512@2x.png").convert("RGBA")

ocean = Image.open(resources / "AppIconVariants/ocean.png").convert("RGBA")
if fallback.size != ocean.size or fallback.tobytes() != ocean.tobytes():
    raise SystemExit("bundle AppIcon.icns does not match the current ocean icon fallback")
PY
then
  record_pass "Bundle app icon fallback matches current crab style"
else
  record_fail "Bundle app icon fallback matches current crab style"
fi
if "$PYTHON_BIN" - "$REPO_ROOT" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1])
resources = root / "apps/macos/Resources"

def frame_sets() -> list[Path]:
    sets = [resources / "CrabSpritesWall"]
    sets.extend(sorted((resources / "CrabSpriteWallVariants").iterdir()))
    return [path for path in sets if path.is_dir()]

expected_idle = {f"idle-{index}.png" for index in range(1, 5)}
expected_intro = {f"recording-intro-{index}.png" for index in range(1, 7)}
expected_recording = expected_intro | {"recording-hold.png", "recording-2.png"}

for frame_dir in frame_sets():
    actual_idle = {path.name for path in frame_dir.glob("idle-*.png")}
    actual_recording = {path.name for path in frame_dir.glob("recording*.png")}
    if actual_idle != expected_idle:
        raise SystemExit(f"{frame_dir} idle frames mismatch: {sorted(actual_idle)}")
    if actual_recording != expected_recording:
        raise SystemExit(f"{frame_dir} recording frames mismatch: {sorted(actual_recording)}")
PY
then
  record_pass "Wall crab animation frames are complete"
else
  record_fail "Wall crab animation frames are complete"
fi
if "$PYTHON_BIN" - "$REPO_ROOT" <<'PY'
from pathlib import Path
from PIL import Image
import sys

root = Path(sys.argv[1])
resources = root / "apps/macos/Resources"

def frame_sets() -> list[Path]:
    sets = [resources / "CrabSpritesWall"]
    sets.extend(sorted((resources / "CrabSpriteWallVariants").iterdir()))
    return [path for path in sets if path.is_dir()]

def rgba(path: Path) -> Image.Image:
    return Image.open(path).convert("RGBA")

def alpha_bbox(image: Image.Image) -> tuple[int, int, int, int]:
    bbox = image.getchannel("A").getbbox()
    if bbox is None:
        raise SystemExit("frame has no visible pixels")
    return bbox

def is_crab_core(pixel: tuple[int, int, int, int]) -> bool:
    red, green, blue, alpha = pixel
    return (
        alpha > 80
        and blue > 70
        and green > 35
        and red < 115
        and (blue > red + 35 or green > red + 35)
    )

def mask_bbox(image: Image.Image) -> tuple[int, int, int, int]:
    pixels = image.load()
    xs = []
    ys = []
    for y in range(image.height):
        for x in range(image.width):
            if is_crab_core(pixels[x, y]):
                xs.append(x)
                ys.append(y)
    if not xs:
        raise SystemExit("frame has no crab core pixels")
    return (min(xs), min(ys), max(xs) + 1, max(ys) + 1)

def assert_recording_frame_integrity(frame_dir: Path) -> None:
    idle_path = frame_dir / "idle-1.png"
    recording_paths = sorted(frame_dir.glob("recording*.png"))
    if not idle_path.exists() or not recording_paths:
        raise SystemExit(f"{frame_dir} is missing idle or recording frames")

    idle = rgba(idle_path)
    idle_core = mask_bbox(idle)
    idle_core_width = idle_core[2] - idle_core[0]
    idle_core_height = idle_core[3] - idle_core[1]
    idle_core_center_y = (idle_core[1] + idle_core[3]) / 2

    for recording_path in recording_paths:
        recording = rgba(recording_path)
        if recording.size != idle.size:
            raise SystemExit(f"{recording_path} changes the crab canvas size")

        corners = [
            recording.getpixel((0, 0)),
            recording.getpixel((recording.width - 1, 0)),
            recording.getpixel((0, recording.height - 1)),
            recording.getpixel((recording.width - 1, recording.height - 1)),
        ]
        if any(pixel[3] != 0 for pixel in corners):
            raise SystemExit(f"{recording_path} has a visible canvas corner")

        visible = alpha_bbox(recording)
        if visible[3] >= recording.height:
            raise SystemExit(f"{recording_path} clips visible boom pixels at the bottom edge")

        core = mask_bbox(recording)
        core_width = core[2] - core[0]
        core_height = core[3] - core[1]
        core_center_y = (core[1] + core[3]) / 2
        width_ratio = core_width / idle_core_width
        height_ratio = core_height / idle_core_height
        if not 0.90 <= width_ratio <= 1.03:
            raise SystemExit(f"{recording_path} changes crab body width ratio to {width_ratio:.3f}")
        if not 0.90 <= height_ratio <= 1.08:
            raise SystemExit(f"{recording_path} changes crab body height ratio to {height_ratio:.3f}")
        if abs(core[2] - idle_core[2]) > 3:
            raise SystemExit(f"{recording_path} moves the wall-side crab anchor")
        if abs(core_center_y - idle_core_center_y) > 14:
            raise SystemExit(f"{recording_path} moves the crab body too far vertically")

assert_recording_frame_integrity(resources / "CrabSpritesWall")
PY
then
  record_pass "Wall boom frames preserve body scale and canvas integrity"
else
  record_fail "Wall boom frames preserve body scale and canvas integrity"
fi
if "$PYTHON_BIN" - "$REPO_ROOT" <<'PY'
from pathlib import Path
from PIL import Image
import sys

root = Path(sys.argv[1])
source = root / "assets/mascot/generated-candidates/crab-boom-pet-sheet-v4-alpha.png"
if not source.exists():
    raise SystemExit("generated recording sprite sheet is missing")

sheet = Image.open(source).convert("RGBA")
for point in [(0, 0), (sheet.width - 1, 0), (0, sheet.height - 1), (sheet.width - 1, sheet.height - 1)]:
    if sheet.getpixel(point)[3] != 0:
        raise SystemExit(f"generated sheet has a visible corner at {point}")

frame_count = 8
if sheet.width < frame_count:
    raise SystemExit("generated sheet is narrower than its frame count")
for index in range(frame_count):
    left = round(index * sheet.width / frame_count)
    right = round((index + 1) * sheet.width / frame_count)
    bbox = sheet.crop((left, 0, right, sheet.height)).getchannel("A").getbbox()
    if bbox is None:
        raise SystemExit(f"generated sheet frame {index + 1} is blank")
PY
then
  record_pass "Wall recording animation uses generated sprite sheet source"
else
  record_fail "Wall recording animation uses generated sprite sheet source"
fi
if "$PYTHON_BIN" - "$REPO_ROOT" <<'PY'
from pathlib import Path
from PIL import Image
import sys

root = Path(sys.argv[1])
resources = root / "apps/macos/Resources"

def frame_sets() -> list[Path]:
    sets = [resources / "CrabSpritesWall"]
    sets.extend(sorted((resources / "CrabSpriteWallVariants").iterdir()))
    return [path for path in sets if path.is_dir()]

def alpha_bbox(path: Path) -> tuple[int, int, int, int]:
    bbox = Image.open(path).convert("RGBA").getchannel("A").getbbox()
    if bbox is None:
        raise SystemExit(f"{path} has no visible pixels")
    return bbox

for frame_dir in frame_sets():
    idle_right = alpha_bbox(frame_dir / "idle-1.png")[2]
    for recording_path in sorted(frame_dir.glob("recording*.png")):
        recording_right = alpha_bbox(recording_path)[2]
        if recording_right < idle_right - 1:
            raise SystemExit(
                f"{recording_path} moved the wall contact edge left "
                f"(idle={idle_right}, recording={recording_right})"
            )
PY
then
  record_pass "Wall boom frames keep wall contact edge"
else
  record_fail "Wall boom frames keep wall contact edge"
fi
if "$PYTHON_BIN" - "$REPO_ROOT" <<'PY'
from pathlib import Path
from PIL import Image
import sys

root = Path(sys.argv[1])
resources = root / "apps/macos/Resources"
base_dir = resources / "CrabSpritesWall"
variant_root = resources / "CrabSpriteWallVariants"
base_idle = Image.open(base_dir / "idle-1.png").convert("RGBA")
base_recording = Image.open(base_dir / "recording-hold.png").convert("RGBA")
idle_pixels = base_idle.load()
recording_pixels = base_recording.load()
y_offset = (base_recording.height - base_idle.height) // 2

def is_neutral(pixel):
    red, green, blue, alpha = pixel
    if alpha < 96:
        return False
    chroma = max(red, green, blue) - min(red, green, blue)
    luma = (0.2126 * red) + (0.7152 * green) + (0.0722 * blue)
    return chroma <= 44 or luma <= 34

hardware_coords = []
for y in range(base_recording.height):
    for x in range(base_recording.width):
        pixel = recording_pixels[x, y]
        if not is_neutral(pixel):
            continue

        idle_y = y - y_offset
        if 0 <= idle_y < base_idle.height and x < base_idle.width:
            idle_pixel = idle_pixels[x, idle_y]
            if idle_pixel[3] > 0 and all(abs(pixel[channel] - idle_pixel[channel]) <= 3 for channel in range(4)):
                continue
        hardware_coords.append((x, y, pixel))

if len(hardware_coords) < 300:
    raise SystemExit("No neutral boom hardware pixels found")

for variant_dir in sorted(path for path in variant_root.iterdir() if path.is_dir()):
    variant = Image.open(variant_dir / "recording-hold.png").convert("RGBA")
    variant_pixels = variant.load()
    for x, y, expected in hardware_coords:
        actual = variant_pixels[x, y]
        if any(abs(actual[channel] - expected[channel]) > 3 for channel in range(3)):
            raise SystemExit(f"{variant_dir.name} recolors boom hardware at {(x, y)}")
        if actual[3] + 3 < expected[3]:
            raise SystemExit(f"{variant_dir.name} recolors boom hardware at {(x, y)}")
PY
then
  record_pass "Wall boom hardware stays neutral across color variants"
else
  record_fail "Wall boom hardware stays neutral across color variants"
fi
if "$PYTHON_BIN" - "$REPO_ROOT" <<'PY'
from pathlib import Path
from PIL import Image
import sys

root = Path(sys.argv[1])
base_dir = root / "apps/macos/Resources/CrabSpritesWall"
idle = Image.open(base_dir / "idle-1.png").convert("RGBA")
idle_pixels = idle.load()

def is_neutral(pixel):
    red, green, blue, alpha = pixel
    if alpha < 96:
        return False
    chroma = max(red, green, blue) - min(red, green, blue)
    luma = (0.2126 * red) + (0.7152 * green) + (0.0722 * blue)
    return chroma <= 44 or luma <= 34

def hardware_centroid(path: Path) -> tuple[float, int]:
    image = Image.open(path).convert("RGBA")
    pixels = image.load()
    xs = []
    for y in range(image.height):
        for x in range(image.width):
            pixel = pixels[x, y]
            if not is_neutral(pixel):
                continue
            idle_pixel = idle_pixels[x, y]
            if idle_pixel[3] > 0 and all(abs(pixel[channel] - idle_pixel[channel]) <= 3 for channel in range(4)):
                continue
            xs.append(x)
    if len(xs) < 180:
        raise SystemExit(f"{path.name} does not contain enough boom hardware pixels")
    return sum(xs) / len(xs), len(xs)

stats = [
    hardware_centroid(base_dir / f"recording-intro-{index}.png")
    for index in range(1, 7)
]
centroids = [centroid for centroid, _ in stats]
counts = [count for _, count in stats]
if len({round(value) for value in centroids}) < 4:
    raise SystemExit(f"Boom intro frames do not use distinct hardware poses: {centroids}")
if max(counts) < counts[0] * 1.15:
    raise SystemExit(f"Boom hardware does not reveal into a fuller held pose: {counts}")
if abs(centroids[-1] - centroids[-2]) > 1.5:
    raise SystemExit(f"Final boom frames do not settle into a stable hold: {centroids}")
hold = Image.open(base_dir / "recording-hold.png").convert("RGBA")
final_intro = Image.open(base_dir / "recording-intro-6.png").convert("RGBA")
if hold.tobytes() != final_intro.tobytes():
    raise SystemExit("Recording hold frame does not match the final intro frame")
PY
then
  record_pass "Wall boom intro uses distinct pulled-out poses"
else
  record_fail "Wall boom intro uses distinct pulled-out poses"
fi
if "$PYTHON_BIN" - "$REPO_ROOT" <<'PY'
from pathlib import Path
from PIL import Image
import sys

root = Path(sys.argv[1])
hold = Image.open(
    root / "apps/macos/Resources/CrabSpritesWall/recording-hold.png"
).convert("RGBA")

handle_pixels = 0
for y in range(130, 134):
    for x in range(136, 140):
        red, green, blue, alpha = hold.getpixel((x, y))
        if alpha < 200:
            continue
        chroma = max(red, green, blue) - min(red, green, blue)
        luma = (0.2126 * red) + (0.7152 * green) + (0.0722 * blue)
        if chroma <= 24 and 35 <= luma <= 90:
            handle_pixels += 1

if handle_pixels < 3:
    raise SystemExit(
        f"Recording hold boom handle does not reach the claw grip: {handle_pixels}"
    )
PY
then
  record_pass "Wall boom handle reaches claw grip"
else
  record_fail "Wall boom handle reaches claw grip"
fi
if "$PYTHON_BIN" - "$REPO_ROOT" <<'PY'
from pathlib import Path
from PIL import Image
import sys

root = Path(sys.argv[1])
base_dir = root / "apps/macos/Resources/CrabSpritesWall"
black_dir = root / "apps/macos/Resources/CrabSpriteWallVariants/black"
idle = Image.open(base_dir / "idle-1.png").convert("RGBA")
base = Image.open(base_dir / "recording-hold.png").convert("RGBA")
black = Image.open(black_dir / "recording-hold.png").convert("RGBA")
idle_pixels = idle.load()
base_pixels = base.load()
black_pixels = black.load()

colored_added = []
for y in range(base.height):
    for x in range(base.width):
        pixel = base_pixels[x, y]
        if pixel[3] < 128:
            continue
        idle_pixel = idle_pixels[x, y]
        if idle_pixel[3] > 0 and all(abs(pixel[channel] - idle_pixel[channel]) <= 3 for channel in range(4)):
            continue
        red, green, blue, _ = pixel
        if max(red, green, blue) - min(red, green, blue) > 60:
            colored_added.append((x, y, pixel))

if len(colored_added) < 40:
    raise SystemExit("No crab-colored grip pixels found in recording hold")

changed = 0
for x, y, expected in colored_added:
    actual = black_pixels[x, y]
    if any(abs(actual[channel] - expected[channel]) > 12 for channel in range(3)):
        changed += 1

if changed / len(colored_added) < 0.75:
    raise SystemExit("Crab grip pixels are not following color variants")
PY
then
  record_pass "Wall crab grip follows color variants"
else
  record_fail "Wall crab grip follows color variants"
fi
if "$PYTHON_BIN" - "$REPO_ROOT" <<'PY'
import importlib.util
import re
from pathlib import Path
import sys

root = Path(sys.argv[1])
swift_source = (root / "apps/macos/Sources/Views/FloatingIndicator.swift").read_text()
enum_match = re.search(
    r"enum CrabColorVariant:[^{]+\{\n(?P<body>.*?)\n\n    var id:",
    swift_source,
    re.S,
)
if enum_match is None:
    raise SystemExit("Could not find CrabColorVariant cases")
enum_cases = re.findall(r"^\s*case\s+([A-Za-z][A-Za-z0-9_]*)\s*$", enum_match.group("body"), re.M)

sync_script = root / "scripts/sync-mascot-assets.py"
spec = importlib.util.spec_from_file_location("sync_mascot_assets", sync_script)
sync_mascot_assets = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(sync_mascot_assets)
script_cases = list(sync_mascot_assets.ICON_COLOR_VARIANTS.keys())
if enum_cases != script_cases:
    raise SystemExit(f"Variant enum/script mismatch: {enum_cases} != {script_cases}")

resources = root / "apps/macos/Resources"
expected = set(enum_cases)
checks = {
    "CrabSpriteVariants": {path.name for path in (resources / "CrabSpriteVariants").iterdir() if path.is_dir()},
    "CrabSpriteWallVariants": {
        path.name for path in (resources / "CrabSpriteWallVariants").iterdir() if path.is_dir()
    },
    "AppIconVariants": {
        path.stem for path in (resources / "AppIconVariants").glob("*.png")
    },
}
for label, actual in checks.items():
    if actual != expected:
        raise SystemExit(f"{label} variants mismatch: missing={sorted(expected - actual)} extra={sorted(actual - expected)}")
PY
then
  record_pass "Crab color variants match enum and generated assets"
else
  record_fail "Crab color variants match enum and generated assets"
fi
if "$PYTHON_BIN" - "$REPO_ROOT" <<'PY'
from pathlib import Path
from PIL import Image
import sys

root = Path(sys.argv[1])
wall_variants = root / "apps/macos/Resources/CrabSpriteWallVariants"
neutral_order = ["black", "graphite", "pearl"]

def visible_luma(path: Path) -> float:
    image = Image.open(path).convert("RGBA")
    samples = []
    pixel_bytes = image.tobytes()
    for index in range(0, len(pixel_bytes), 4):
        red, green, blue, alpha = pixel_bytes[index:index + 4]
        if alpha > 0:
            samples.append((0.2126 * red) + (0.7152 * green) + (0.0722 * blue))
    if not samples:
        raise SystemExit(f"{path} has no visible pixels")
    return sum(samples) / len(samples)

frame_names = ["idle-1.png"]
for recording_path in sorted((wall_variants / "black").glob("recording*.png")):
    frame_names.append(recording_path.name)

for frame_name in frame_names:
    values = [visible_luma(wall_variants / variant / frame_name) for variant in neutral_order]
    if not values[0] < values[1] < values[2]:
        raise SystemExit(f"{frame_name} neutral luminance order is wrong: {values}")
PY
then
  record_pass "Neutral crab variants preserve luminance order"
else
  record_fail "Neutral crab variants preserve luminance order"
fi
assert_contains "Boom crab scale matches idle crab" "$MACOS_DIR/Sources/Views/FloatingIndicator.swift" "boomScale"
assert_contains "Crab idle uses clean pose cycle" "$MACOS_DIR/Sources/Views/FloatingIndicator.swift" "\"idle-4\""
assert_not_contains "Crab idle avoids blended wall frames" "$MACOS_DIR/Sources/Views/FloatingIndicator.swift" "\"idle-5\""
assert_contains "Crab crawl offset is animated" "$MACOS_DIR/Sources/Views/FloatingIndicator.swift" "withAnimation\\(\\.easeInOut"
assert_contains "Crab recording uses intro frames" "$MACOS_DIR/Sources/Views/FloatingIndicator.swift" "boomIntroFrameNames"
assert_contains "Crab recording holds final boom frame" "$MACOS_DIR/Sources/Views/FloatingIndicator.swift" "boomHoldFrameName"
assert_contains "Crab recording reverses before walking" "$MACOS_DIR/Sources/Views/FloatingIndicator.swift" "animateBoomOutro"
assert_contains "Crab frame swaps avoid implicit fade" "$MACOS_DIR/Sources/Views/FloatingIndicator.swift" "Transaction\\(animation: nil\\)"
assert_contains "Crab sprite image identity follows frame" "$MACOS_DIR/Sources/Views/FloatingIndicator.swift" "\\.id\\(frameName\\)"
assert_contains "Crab sprite image uses identity transition" "$MACOS_DIR/Sources/Views/FloatingIndicator.swift" "\\.transition\\(\\.identity\\)"
assert_contains "Crab processing spinner has tuned duration" "$MACOS_DIR/Sources/Views/FloatingIndicator.swift" "processingSpinDuration"
assert_contains "Crab processing spinner rotates continuously" "$MACOS_DIR/Sources/Views/FloatingIndicator.swift" "processingRotation \\+= 360"
assert_contains "Wall boom frames use generated sprite sheet" "$REPO_ROOT/scripts/sync-mascot-assets.py" "GENERATED_WALL_RECORDING_SHEET"
assert_not_contains "Wall boom frames avoid procedural pose overlay" "$REPO_ROOT/scripts/sync-mascot-assets.py" "WALL_BOOM_POSES"
assert_not_contains "Wall boom frames avoid reveal-mask animation" "$REPO_ROOT/scripts/sync-mascot-assets.py" "slide_reveal_overlay"
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
