import AppKit
import ServiceManagement
import ShoutOutCore
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var transcription: TranscriptionService
    @EnvironmentObject var languagePass: LanguagePassService
    @EnvironmentObject var permissions: PermissionManager
    @EnvironmentObject var usageStats: UsageStatsStore

    @AppStorage("removeFillerWords") private var removeFillerWords = true
    @AppStorage(Defaults.appendTrailingSpace) private var appendTrailingSpace = true
    @AppStorage(Defaults.smartSpacing) private var smartSpacing = true
    @AppStorage(Defaults.showInDock) private var showInDock = true
    @AppStorage(Defaults.dimSystemAudio) private var dimSystemAudio = true
    @AppStorage(Defaults.overlayStyle) private var overlayStyle = OverlayStyle.crab.rawValue
    @AppStorage(Defaults.crabColorVariant) private var crabColorVariant = CrabColorVariant.ocean.rawValue
    @AppStorage(Defaults.hotkeyTrigger) private var hotkeyTrigger = HotkeyTrigger.defaultTrigger.rawValue
    @AppStorage(Defaults.boringMode) private var boringMode = false

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var isConfirmingStatsClear = false
    @State private var advancedControlsExpanded = false

    var body: some View {
        Form {
            // Shortcut
            Section {
                Picker(selection: $hotkeyTrigger) {
                    ForEach(HotkeyTrigger.allCases) { trigger in
                        Text(trigger.displayName).tag(trigger.rawValue)
                    }
                } label: {
                    Label("Shortcut", systemImage: "keyboard")
                }
                .onChange(of: hotkeyTrigger) { _, _ in
                    (NSApp.delegate as? AppDelegate)?.restartHotkey()
                }

                VStack(alignment: .leading, spacing: 4) {
                    Label("Trigger Modes", systemImage: "hand.tap")
                    Text("Hold shortcut: push-to-talk\nDouble-press shortcut: hands-free (press again to stop)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Toggle(isOn: $boringMode) {
                    Label("Boring mode", systemImage: "rectangle.dashed")
                }
                .onChange(of: boringMode) { _, newValue in
                    overlayStyle = newValue ? OverlayStyle.capsule.rawValue : OverlayStyle.crab.rawValue
                    (NSApp.delegate as? AppDelegate)?.refreshOverlay()
                }

                Picker(selection: $overlayStyle) {
                    Text("Crab").tag(OverlayStyle.crab.rawValue)
                    Text("Classic").tag(OverlayStyle.capsule.rawValue)
                    Text("Off").tag(OverlayStyle.off.rawValue)
                } label: {
                    Label("Indicator", systemImage: "macwindow.on.rectangle")
                }
                .disabled(boringMode)
                .onChange(of: overlayStyle) { _, _ in
                    (NSApp.delegate as? AppDelegate)?.refreshOverlay()
                }

                Picker(selection: $crabColorVariant) {
                    ForEach(CrabColorVariant.allCases) { variant in
                        CrabColorMenuLabel(variant: variant)
                            .tag(variant.rawValue)
                    }
                } label: {
                    Label("Crab Color", systemImage: "paintpalette")
                }
                .pickerStyle(.menu)
                .disabled(boringMode || overlayStyle != OverlayStyle.crab.rawValue)
                .onChange(of: crabColorVariant) { _, _ in
                    (NSApp.delegate as? AppDelegate)?.refreshOverlay()
                }
            } header: {
                Text("Input")
            }

            // Dictation
            Section {
                Picker(selection: dictationPresetBinding) {
                    ForEach(DictationPreset.allCases) { preset in
                        Text(preset.title).tag(preset)
                    }
                } label: {
                    Label("Mode", systemImage: "waveform.path.ecg")
                }

                VStack(alignment: .leading, spacing: 6) {
                    Label("Selected mode", systemImage: "slider.horizontal.3")
                    Text(transcription.selectedPreset.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack {
                    Label("Status", systemImage: "circle.fill")
                        .foregroundStyle(modelStatusColor)
                    Spacer()
                    Text(modelStatusText)
                        .foregroundStyle(.secondary)
                    if case .error = transcription.modelState {
                        Button("Retry") {
                            Task { await transcription.loadModel() }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                if let progress = transcription.modelState.startupProgress,
                    !transcription.modelState.isReady
                {
                    VStack(alignment: .leading, spacing: 6) {
                        ModelProgressBar(progress: progress, height: 6)
                        Text(modelProgressCaption)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            } header: {
                Text("Dictation")
            }

            Section {
                Picker(selection: $languagePass.selectedStyle) {
                    ForEach(LanguagePassStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                } label: {
                    Label("Writing style", systemImage: "text.quote")
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(languagePass.selectedStyle.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("ShoutOut also cleans stutters, repeated starts, and obvious self-corrections when the local cleanup model is ready.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                HStack {
                    Label("Status", systemImage: "circle.fill")
                        .foregroundStyle(languagePassStatusColor)
                    Spacer()
                    Text(languagePassStatusText)
                        .foregroundStyle(.secondary)
                    if case .error = languagePass.modelState {
                        Button("Retry") {
                            Task { await languagePass.prepareIfNeeded() }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                if let progress = languagePass.modelState.startupProgress,
                    languagePass.isEnabled,
                    !languagePass.modelState.isReady
                {
                    VStack(alignment: .leading, spacing: 6) {
                        ModelProgressBar(progress: progress, height: 6)
                        Text(languagePassProgressCaption)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                if let summary = languagePass.lastRunSummary {
                    HStack {
                        Label("Last cleanup", systemImage: "timer")
                        Spacer()
                        Text(languagePassSummaryText(summary))
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Writing")
            }

            Section {
                DisclosureGroup(isExpanded: $advancedControlsExpanded) {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle(isOn: languagePassEnabledBinding) {
                            Label("Language cleanup", systemImage: "sparkles")
                        }
                        AdvancedSettingDescription(
                            "Runs the local cleanup model after transcription. If it is off, slow, or unsure, ShoutOut pastes the transcript without the LM pass."
                        )

                        Picker(selection: $transcription.selectedBackend) {
                            ForEach(transcription.availableBackends) { backend in
                                Text(backend.displayName).tag(backend)
                            }
                        } label: {
                            Label("Engine", systemImage: "waveform.path.ecg")
                        }
                        .onChange(of: transcription.selectedBackend) {
                            permissions.refresh()
                            Task { await transcription.loadModel() }
                        }
                        AdvancedSettingDescription(
                            "Exact transcription backend. The normal mode picker is safer; use this when debugging permissions, startup, or device-specific behavior."
                        )

                        if transcription.selectedBackend.requiresManagedModel {
                            Picker(selection: $transcription.selectedModel) {
                                ForEach(TranscriptionModelOption.all) { option in
                                    Text(option.title).tag(option.id)
                                }
                            } label: {
                                Label("Model", systemImage: "cpu")
                            }
                            .onChange(of: transcription.selectedModel) {
                                Task { await transcription.loadModel() }
                            }

                            Text(TranscriptionModelOption.option(for: transcription.selectedModel).detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            AdvancedSettingDescription(
                                "Exact WhisperKit model. Changing it unloads the current model and prepares the selected one."
                            )
                        }

                        Toggle(isOn: $removeFillerWords) {
                            Label("Remove filler words", systemImage: "text.badge.minus")
                        }
                        AdvancedSettingDescription(
                            "Removes simple filler like um, uh, and you know before the language cleanup pass."
                        )

                        Toggle(isOn: $smartSpacing) {
                            Label("Smart spacing", systemImage: "text.cursor")
                        }
                        AdvancedSettingDescription(
                            "Uses nearby text around the cursor to avoid extra spaces and keep mid-sentence insertions natural."
                        )

                        Toggle(isOn: $appendTrailingSpace) {
                            Label("Fallback trailing space", systemImage: "arrow.right.to.line")
                        }
                        AdvancedSettingDescription(
                            "Adds a trailing space when ShoutOut cannot inspect the focused field's surrounding text."
                        )
                    }
                    .padding(.top, 6)
                } label: {
                    Label("Advanced controls", systemImage: "wrench.adjustable")
                }

                Text("Most people can leave these alone. They expose exact engines, model choices, and paste cleanup fallbacks for debugging or unusual Macs.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("Advanced")
            }

            // Insights
            Section {
                StatsRow(title: "Today", summary: usageStats.todaySummary)
                StatsRow(title: "All time", summary: usageStats.allTimeSummary)

                if let lastSession = usageStats.recentSessions.first {
                    HStack {
                        Label("Last dictation", systemImage: "clock")
                        Spacer()
                        Text("\(lastSession.wordCount) words · \(lastSession.wordsPerMinute) WPM")
                            .foregroundStyle(.secondary)
                    }

                }

                Button("Clear Stats", role: .destructive) {
                    isConfirmingStatsClear = true
                }
                .disabled(usageStats.recentSessions.isEmpty)
            } header: {
                Text("Insights")
            }

            // General
            Section {
                Toggle(isOn: $launchAtLogin) {
                    Label("Launch at Login", systemImage: "arrow.right.circle")
                }
                .onChange(of: launchAtLogin) { _, newValue in
                    do {
                        if newValue {
                            try SMAppService.mainApp.register()
                        } else {
                            try SMAppService.mainApp.unregister()
                        }
                    } catch {
                        launchAtLogin = !newValue
                    }
                }

                Toggle(isOn: $showInDock) {
                    Label("Show in Dock", systemImage: "dock.rectangle")
                }
                .onChange(of: showInDock) { _, _ in
                    (NSApp.delegate as? AppDelegate)?.applyDockVisibilityPreference()
                }

                Toggle(isOn: $dimSystemAudio) {
                    Label("Dim system audio while recording", systemImage: "speaker.wave.1")
                }
            } header: {
                Text("General")
            }

            // Permissions
            Section {
                HStack {
                    Label("Current app", systemImage: "app.badge")
                    Spacer()
                    Text(permissions.statusText)
                        .foregroundStyle(permissions.missingPermissionNames.isEmpty ? .green : .orange)
                        .lineLimit(1)
                }

                HStack {
                    Label("Microphone", systemImage: "mic")
                    Spacer()
                    if permissions.hasMicrophone {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button("Grant") {
                            Task { await permissions.requestMicrophone() }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                if transcription.selectedBackend.requiresSpeechRecognitionPermission {
                    HStack {
                        Label("Speech Recognition", systemImage: "waveform")
                        Spacer()
                        if permissions.hasSpeechRecognition {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Button("Grant") {
                                Task { await permissions.requestSpeechRecognition() }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }

                HStack {
                    Label("Accessibility", systemImage: "hand.raised")
                    Spacer()
                    if permissions.hasAccessibility {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button("Grant") {
                            permissions.requestAccessibility()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                HStack {
                    Label("Input Monitoring", systemImage: "keyboard")
                    Spacer()
                    if permissions.hasInputMonitoring {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button("Grant") {
                            permissions.requestInputMonitoring()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                HStack {
                    Button("Open Missing") {
                        permissions.openFirstMissingPermissionPane()
                    }
                    .buttonStyle(.bordered)
                    .disabled(permissions.missingPermissionNames.isEmpty)

                    Button("Refresh") {
                        permissions.refresh()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            } header: {
                Text("Permissions")
            }

            // Storage
            Section {
                HStack {
                    Label("Whisper model data", systemImage: "internaldrive")
                    Spacer()
                    Text(transcription.modelsDiskUsage)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text(TranscriptionService.modelsDirectory.path)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Show in Finder") {
                        NSWorkspace.shared.selectFile(
                            nil,
                            inFileViewerRootedAtPath: TranscriptionService.modelsDirectory.path
                        )
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            } header: {
                Text("Storage")
            }

            Section {
                HStack {
                    Label("Runtime log", systemImage: "doc.text.magnifyingglass")
                    Spacer()
                    Button("Show in Finder") {
                        NSWorkspace.shared.selectFile(
                            RuntimeLog.logURL.path,
                            inFileViewerRootedAtPath: RuntimeLog.logURL.deletingLastPathComponent()
                                .path
                        )
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                Text(RuntimeLog.logURL.path)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack {
                    Label("Support bundle", systemImage: "shippingbox")
                    Spacer()
                    Button("Export Diagnostics") {
                        exportDiagnostics()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                Text("Includes build info, runtime logs, and recent crash reports. It does not include audio, transcripts, or clipboard contents.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("Diagnostics")
            }

            // About
            Section {
                HStack {
                    Text("ShoutOut")
                    Spacer()
                    Text(AppVersionInfo.displayWithCommit)
                        .foregroundStyle(.secondary)
                }
                if let builtAt = AppVersionInfo.builtAt {
                    HStack {
                        Text("Built")
                        Spacer()
                        Text(builtAt)
                            .foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Label("Updates", systemImage: "arrow.triangle.2.circlepath")
                    Spacer()
                    Text(AppUpdaterConfiguration.statusText)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text(AppUpdaterConfiguration.feedURLString)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Check") {
                        (NSApp.delegate as? AppDelegate)?.checkForUpdates()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                Button("Copy Version Info") {
                    copyVersionInfo()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Text("Local voice-to-text with swappable on-device engines.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } header: {
                Text("About")
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 420, maxWidth: .infinity, minHeight: 640, alignment: .top)
        .alert("Clear local stats?", isPresented: $isConfirmingStatsClear) {
            Button("Clear Stats", role: .destructive) {
                try? usageStats.clear()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes your local word counts, sessions, and latency history from this Mac.")
        }
    }

    // MARK: - Helpers

    private func copyVersionInfo() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(AppVersionInfo.diagnosticsSummary, forType: .string)
    }

    private func exportDiagnostics() {
        do {
            let result = try DiagnosticsExporter.export(
                transcription: transcription,
                permissions: permissions
            )
            NSWorkspace.shared.selectFile(
                result.archiveURL.path,
                inFileViewerRootedAtPath: result.archiveURL.deletingLastPathComponent().path
            )
        } catch {
            RuntimeLog.write("diagnostics export failed error=\(error.localizedDescription)")
            NSAlert(error: error).runModal()
        }
    }

    private var modelStatusColor: Color {
        switch transcription.modelState {
        case .ready: return .green
        case .loading, .downloading: return .orange
        case .error: return .red
        case .unloaded: return .gray
        }
    }

    private var modelStatusText: String {
        switch transcription.modelState {
        case .ready: return "Ready"
        case .loading: return "Loading..."
        case .downloading(let p): return "Downloading \(Int(p * 100))%"
        case .error(let msg): return msg
        case .unloaded: return "Not loaded"
        }
    }

    private var modelProgressCaption: String {
        switch transcription.modelState {
        case .downloading(let progress):
            return "Downloading local dictation model \(Int(progress * 100))%"
        case .loading:
            if transcription.selectedBackend == .whisperKit {
                return "Download complete. Preparing the local model."
            }
            return "Preparing \(transcription.selectedBackend.displayName)."
        default:
            return ""
        }
    }

    private var languagePassEnabledBinding: Binding<Bool> {
        Binding(
            get: { languagePass.isEnabled },
            set: { languagePass.isEnabled = $0 }
        )
    }

    private var dictationPresetBinding: Binding<DictationPreset> {
        Binding(
            get: { transcription.selectedPreset },
            set: { applyDictationPreset($0) }
        )
    }

    private func applyDictationPreset(_ preset: DictationPreset) {
        transcription.applyPreset(preset)
        languagePass.isEnabled = true
        permissions.refresh()
        Task {
            await transcription.loadModel()
        }
        languagePass.warmUpIfEnabled()
    }

    private var languagePassStatusColor: Color {
        guard languagePass.isEnabled else {
            return .gray
        }
        switch languagePass.modelState {
        case .ready: return .green
        case .loading, .downloading: return .orange
        case .error: return .red
        case .unloaded: return .gray
        }
    }

    private var languagePassStatusText: String {
        guard languagePass.isEnabled else {
            return "Off"
        }
        switch languagePass.modelState {
        case .ready:
            return "Ready"
        case .loading:
            return "Loading..."
        case .downloading(let progress):
            return "Downloading \(Int(progress * 100))%"
        case .error(let message):
            return message
        case .unloaded:
            return "Warming up"
        }
    }

    private var languagePassProgressCaption: String {
        switch languagePass.modelState {
        case .downloading(let progress):
            return "Downloading \(Int(progress * 100))% of the local cleanup model"
        case .loading:
            return "Preparing language cleanup."
        default:
            return ""
        }
    }

    private func languagePassSummaryText(_ summary: LanguagePassRunSummary) -> String {
        var parts: [String] = []
        if let wallMs = summary.wallMs {
            parts.append("\(wallMs) ms")
        }
        if summary.accepted {
            parts.append(summary.changed ? "cleaned" : "accepted")
        } else {
            parts.append(summary.fallbackReason ?? "fallback")
        }
        return parts.joined(separator: " · ")
    }
}

private struct CrabColorMenuLabel: View {
    let variant: CrabColorVariant

    var body: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(variant.swatchColor)
                .overlay {
                    Rectangle()
                        .stroke(.primary.opacity(0.32), lineWidth: 1)
                }
                .overlay(alignment: .topLeading) {
                    Rectangle()
                        .fill(.white.opacity(0.20))
                        .frame(height: 4)
                }
                .frame(width: 28, height: 18)
            Text(variant.displayName)
        }
    }
}

private struct AdvancedSettingDescription: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct EngineGuideRow: View {
    let backend: TranscriptionBackend

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text(backend.displayName)
                    .font(.caption.weight(.semibold))
                Text("\(backend.speedLabel) speed")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("\(backend.qualityLabel) quality")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Text(backend.detailText)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct StatsRow: View {
    let title: String
    let summary: UsageStatsSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(title, systemImage: "speedometer")
                Spacer()
                Text("\(summary.averageWordsPerMinute) WPM")
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 16) {
                Text("\(summary.wordCount) words")
                Text("\(summary.sessionCount) sessions")
                Text(durationText)
            }
            .font(.caption)
            .foregroundStyle(.tertiary)

        }
    }

    private var durationText: String {
        let minutes = Int(round(summary.totalDuration / 60))
        if minutes < 1 {
            return "<1 min"
        }
        return "\(minutes) min"
    }
}
