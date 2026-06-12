import ServiceManagement
import ShoutOutCore
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var transcription: TranscriptionService
    @EnvironmentObject var permissions: PermissionManager
    @EnvironmentObject var usageStats: UsageStatsStore

    @AppStorage("removeFillerWords") private var removeFillerWords = true
    @AppStorage(Defaults.showInDock) private var showInDock = true
    @AppStorage(Defaults.dimSystemAudio) private var dimSystemAudio = true
    @AppStorage(Defaults.overlayStyle) private var overlayStyle = OverlayStyle.crab.rawValue

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            // Shortcut
            Section {
                HStack {
                    Label("Shortcut", systemImage: "keyboard")
                    Spacer()
                    Text("Fn (Globe)")
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Label("Trigger Modes", systemImage: "hand.tap")
                    Text("Hold Fn: push-to-talk\nDouble-press Fn: hands-free (press again to stop)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            } header: {
                Text("Input")
            }

            // Model
            Section {
                Picker(selection: $transcription.selectedModel) {
                    Text("Tiny (~75 MB)").tag("tiny")
                    Text("Base (~142 MB)").tag("base")
                    Text("Small (~466 MB)").tag("small")
                    Text("Medium (~1.5 GB)").tag("medium")
                    Text("Large v3 Turbo (~626 MB)").tag("large-v3-v20240930_626MB")
                } label: {
                    Label("Model", systemImage: "cpu")
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
                .onChange(of: transcription.selectedModel) {
                    Task { await transcription.loadModel() }
                }
            } header: {
                Text("Transcription")
            }

            // Post-processing
            Section {
                Toggle(isOn: $removeFillerWords) {
                    Label("Remove filler words", systemImage: "text.badge.minus")
                }
            } header: {
                Text("Post-processing")
            }

            DictionarySettingsView(store: transcription.dictionaryStore)

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
                    try? usageStats.clear()
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

                Picker(selection: $overlayStyle) {
                    Text("Crab").tag(OverlayStyle.crab.rawValue)
                    Text("Classic").tag(OverlayStyle.capsule.rawValue)
                    Text("Off").tag(OverlayStyle.off.rawValue)
                } label: {
                    Label("Overlay", systemImage: "macwindow.on.rectangle")
                }
                .onChange(of: overlayStyle) { _, _ in
                    (NSApp.delegate as? AppDelegate)?.refreshOverlay()
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
                    Label("Model data", systemImage: "internaldrive")
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
            } header: {
                Text("Diagnostics")
            }

            // About
            Section {
                HStack {
                    Text("Shout Out")
                    Spacer()
                    Text("v0.2.0")
                        .foregroundStyle(.secondary)
                }
                Text("Local voice-to-text powered by WhisperKit. Based on MIT-licensed Inputalk.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } header: {
                Text("About")
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 720)
    }

    // MARK: - Helpers

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
}

private struct DictionarySettingsView: View {
    @ObservedObject var store: DictionaryStore

    @State private var phrase = ""
    @State private var aliasesText = ""
    @State private var errorMessage: String?

    var body: some View {
        Section {
            if store.entries.isEmpty {
                Text("No dictionary entries")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.entries) { entry in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.phrase)
                            if !entry.aliases.isEmpty {
                                Text(entry.aliases.joined(separator: ", "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        Spacer()
                        Button(role: .destructive) {
                            try? store.deleteEntry(id: entry.id)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }

            Divider()

            TextField("Word or phrase", text: $phrase)
            TextField("Heard as, comma or line separated", text: $aliasesText, axis: .vertical)
                .lineLimit(2...4)

            HStack {
                Button("Add") {
                    addEntry()
                }
                .buttonStyle(.borderedProminent)
                .disabled(phrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button("Reset Defaults") {
                    try? store.resetToDefaults()
                }
                .buttonStyle(.bordered)

                Spacer()
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Dictionary")
        } footer: {
            Text("Use this for names and acronyms Whisper tends to miss, like Yuxin.")
        }
    }

    private func addEntry() {
        do {
            try store.addEntry(phrase: phrase, aliasesText: aliasesText)
            phrase = ""
            aliasesText = ""
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
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
