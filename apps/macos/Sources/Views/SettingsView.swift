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

            // Model
            Section {
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

                VStack(alignment: .leading, spacing: 6) {
                    Label("Selected engine", systemImage: "slider.horizontal.3")
                    Text(transcription.selectedBackend.detailText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Label("Engine guide", systemImage: "speedometer")

                    ForEach(TranscriptionBackend.allCases) { backend in
                        EngineGuideRow(backend: backend)
                    }

                    Text("Available options depend on your macOS version.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

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

                    HStack {
                        Label("Model detail", systemImage: "tag")
                        Spacer()
                        Text(TranscriptionModelOption.option(for: transcription.selectedModel).detail)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
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
                Text("Transcription")
            }

            // Post-processing
            Section {
                Toggle(isOn: $removeFillerWords) {
                    Label("Remove filler words", systemImage: "text.badge.minus")
                }

                Toggle(isOn: $smartSpacing) {
                    Label("Smart spacing", systemImage: "text.cursor")
                }

                Toggle(isOn: $appendTrailingSpace) {
                    Label("Fallback trailing space", systemImage: "arrow.right.to.line")
                }
            } header: {
                Text("Post-processing")
            }

            Section {
                Toggle(isOn: languagePassEnabledBinding) {
                    Label("Language cleanup", systemImage: "sparkles")
                }

                VStack(alignment: .leading, spacing: 6) {
                    Label("What it does", systemImage: "wand.and.stars")
                    Text("Runs a fast local model after transcription to clean stutters, repeated starts, and obvious self-corrections. If it is slow or unsure, ShoutOut pastes the normal transcript.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Picker(selection: $languagePass.selectedModelID) {
                    ForEach(LanguagePassModelOption.all) { option in
                        Text(option.title).tag(option.id)
                    }
                } label: {
                    Label("Cleanup model", systemImage: "cpu")
                }
                .disabled(!languagePass.isEnabled)
                .onChange(of: languagePass.selectedModelID) {
                    Task { await languagePass.prepareIfNeeded() }
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
                Text("Writing cleanup")
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

                    if let performance = lastSession.performance {
                        HStack {
                            Label("Last latency", systemImage: "timer")
                            Spacer()
                            Text(performanceLatencyText(performance))
                                .foregroundStyle(.secondary)
                        }
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
                Text("Local voice-to-text with swappable on-device engines. Based on MIT-licensed Inputalk.")
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
            return "Downloading \(Int(progress * 100))% of \(transcription.selectedModel)"
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
            return "Not loaded"
        }
    }

    private var languagePassProgressCaption: String {
        switch languagePass.modelState {
        case .downloading(let progress):
            return "Downloading \(Int(progress * 100))% of \(languagePass.selectedModel.title)"
        case .loading:
            return "Preparing \(languagePass.selectedModel.title)."
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

            if let performanceText {
                Text(performanceText)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var performanceText: String? {
        var parts: [String] = []
        if let pressMs = summary.averagePressToRecordStartMs {
            parts.append("Fn->rec \(pressMs) ms")
        }
        if let pasteMs = summary.averageStopToPasteMs {
            parts.append("stop->paste \(pasteMs) ms")
        }
        if let transcriptionMs = summary.averageTranscriptionWallMs {
            parts.append("ASR \(transcriptionMs) ms")
        }
        if let rtf = summary.averageRealTimeFactor {
            parts.append("RTF \(String(format: "%.2f", rtf))")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var durationText: String {
        let minutes = Int(round(summary.totalDuration / 60))
        if minutes < 1 {
            return "<1 min"
        }
        return "\(minutes) min"
    }
}

private func performanceLatencyText(_ performance: UsagePerformanceMetrics) -> String {
    var parts: [String] = []
    if let pressMs = performance.pressToRecordStartMs {
        parts.append("Fn->rec \(pressMs) ms")
    }
    if let pasteMs = performance.stopToPasteMs {
        parts.append("stop->paste \(pasteMs) ms")
    }
    parts.append("ASR \(performance.transcriptionWallMs ?? performance.whisperWallMs) ms")
    if let languageMs = performance.languagePassWallMs {
        parts.append("LM \(languageMs) ms")
    }
    if let rtf = performance.realTimeFactor {
        parts.append("RTF \(String(format: "%.2f", rtf))")
    }
    return parts.joined(separator: " · ")
}
