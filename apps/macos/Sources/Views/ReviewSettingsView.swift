import AppKit
import ServiceManagement
import ShoutOutCore
import SwiftUI
import UniformTypeIdentifiers

struct ReviewSettingsView: View {
    @EnvironmentObject private var transcription: TranscriptionService
    @EnvironmentObject private var languagePass: LanguagePassService
    @EnvironmentObject private var permissions: PermissionManager
    @EnvironmentObject private var history: TranscriptionHistoryStore

    @AppStorage(Defaults.hotkeyTrigger) private var hotkeyTrigger = HotkeyTrigger.defaultTrigger.rawValue
    @AppStorage(Defaults.overlayStyle) private var overlayStyle = OverlayStyle.crab.rawValue
    @AppStorage(Defaults.crabColorVariant) private var crabColorVariant = CrabColorVariant.ocean.rawValue
    @AppStorage(Defaults.dimSystemAudio) private var dimSystemAudio = true
    @AppStorage(Defaults.showInDock) private var showInDock = true
    @AppStorage(Defaults.customIndicatorTint) private var customTintHex = "#8C7AF5"
    @AppStorage(Defaults.usesCustomIndicatorTint) private var usesCustomTint = false

    @Binding var selectedPane: Pane
    @FocusState private var focusedPane: Pane?
    @State private var launchAtLogin: Bool?
    @State private var confirmsHistoryClear = false
    @State private var confirmsStatsClear = false
    @State private var errorMessage: String?

    let tint: Color
    let getUsageStats: @MainActor () -> UsageStatsStore

    enum Pane: String, CaseIterable, Identifiable {
        case dictation = "Dictation"
        case appearance = "Appearance"
        case system = "System"

        var id: Self { self }
    }

    init(tint: Color, selectedPane: Binding<Pane>, getUsageStats: @escaping @MainActor () -> UsageStatsStore) {
        self.tint = tint
        _selectedPane = selectedPane
        self.getUsageStats = getUsageStats
    }

    var body: some View {
        VStack(spacing: 0) {
            settingsTabs
                .padding(.top, 20)
                .padding(.bottom, 12)

            ScrollView {
                Group {
                    switch selectedPane {
                    case .dictation: dictationPane
                    case .appearance: appearancePane
                    case .system: systemPane
                    }
                }
                .frame(maxWidth: ReviewTheme.detailWidth, alignment: .leading)
                .padding(.horizontal, 28)
                .padding(.top, 8)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity)
            }
            .id(selectedPane)
        }
        .reviewWorkspaceSurface()
        .foregroundStyle(ReviewTheme.text)
        .tint(tint)
        .alert("Could not complete the action", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .alert("Clear transcription history?", isPresented: $confirmsHistoryClear) {
            Button("Clear history", role: .destructive) {
                do { try history.clear() }
                catch { errorMessage = error.localizedDescription }
            }
            Button("Cancel", role: .cancel) {}
                .keyboardShortcut(.defaultAction)
        } message: {
            Text("This deletes saved transcript text from this Mac. Usage stats stay intact.")
        }
        .alert("Clear usage stats?", isPresented: $confirmsStatsClear) {
            Button("Clear stats", role: .destructive) {
                do { try getUsageStats().clear() }
                catch { errorMessage = error.localizedDescription }
            }
            Button("Cancel", role: .cancel) {}
                .keyboardShortcut(.defaultAction)
        } message: {
            Text("This deletes local word counts, dictation counts, and performance stats from this Mac. Saved transcription history stays intact.")
        }
    }

    private var settingsTabs: some View {
        HStack(spacing: 2) {
            ForEach(Pane.allCases) { pane in
                Button {
                    selectedPane = pane
                } label: {
                    Text(pane.rawValue)
                        .font(.system(size: 14, weight: selectedPane == pane ? .semibold : .medium))
                        .foregroundStyle(selectedPane == pane ? ReviewTheme.text : ReviewTheme.muted)
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                }
                .buttonStyle(ReviewRowButtonStyle(selected: selectedPane == pane, tint: tint,
                                                 cornerRadius: ReviewTheme.navigationRadius))
                .focusable()
                .focused($focusedPane, equals: pane)
                .focusEffectDisabled()
                .overlay {
                    RoundedRectangle(cornerRadius: ReviewTheme.navigationRadius)
                        .strokeBorder(focusedPane == pane ? ReviewTheme.muted.opacity(0.75) : .clear)
                        .allowsHitTesting(false)
                }
                .accessibilityAddTraits(selectedPane == pane ? .isSelected : [])
            }
        }
        .padding(3)
        .frame(width: 420)
        .background(ReviewTheme.panel, in: RoundedRectangle(cornerRadius: ReviewTheme.navigationRadius + 3))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Settings sections")
        .onMoveCommand { direction in
            let panes = Pane.allCases
            guard direction == .left || direction == .right,
                  let index = panes.firstIndex(where: { $0 == focusedPane }) else { return }
            let next = index + (direction == .right ? 1 : -1)
            guard panes.indices.contains(next) else { return }
            selectedPane = panes[next]
            focusedPane = panes[next]
        }
    }

    private var dictationPane: some View {
        VStack(alignment: .leading, spacing: 26) {
            section("Shortcut") {
                settingRow("Activation shortcut", detail: "Hold to speak. Double-press for hands-free.") {
                    Picker("Activation shortcut", selection: $hotkeyTrigger) {
                        ForEach(HotkeyTrigger.allCases) { trigger in
                            Text(trigger.displayName).tag(trigger.rawValue)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 180, alignment: .trailing)
                    .onChange(of: hotkeyTrigger) { _, _ in
                        (NSApp.delegate as? AppDelegate)?.restartHotkey()
                    }
                }
            }

            if !transcription.modelState.isReady {
                section("Model") {
                    if let progress = transcription.modelState.startupProgress {
                        ProgressView(value: progress)
                            .accessibilityLabel("Downloading dictation model")
                    } else if transcription.modelState == .loading {
                        ProgressView("Preparing dictation")
                            .controlSize(.small)
                    } else if case .error(let message) = transcription.modelState {
                        settingRow("Dictation model unavailable", detail: message) {
                            Button("Try again") { Task { await transcription.loadModel() } }
                        }
                    } else if transcription.modelState == .unloaded {
                        settingRow("Dictation model") {
                            Button("Prepare dictation") { Task { await transcription.loadModel() } }
                        }
                    }
                }
            }

            section("Writing") {
                settingRow("Text cleanup", detail: languagePass.usesMiniEditor
                    ? "Remove fillers and capitalize sentences while keeping your wording."
                    : "Clean up stutters, repeated starts, and self-corrections.") {
                    Toggle("Text cleanup", isOn: $languagePass.isEnabled).labelsHidden()
                }
                if languagePass.isEnabled {
                    if !languagePass.usesMiniEditor {
                        settingRow("Writing style", detail: languagePass.selectedStyle.detail) {
                            Picker("Writing style", selection: $languagePass.selectedStyle) {
                                ForEach(LanguagePassStyle.allCases) { style in
                                    Text(style.title).tag(style)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 180, alignment: .trailing)
                        }
                    }
                    if let progress = languagePass.modelState.startupProgress,
                        !languagePass.modelState.isReady {
                        ProgressView(value: progress)
                            .accessibilityLabel("Preparing text cleanup")
                    }
                    if case .error = languagePass.modelState {
                        HStack {
                            Text("Text cleanup could not start. Dictation still works.")
                                .foregroundStyle(.red)
                            Button("Try Again") { Task { await languagePass.prepareIfNeeded() } }
                        }
                        .font(.system(size: 13))
                    }
                }
            }

            section("Audio") {
                settingRow("While recording", detail: "Dim audio lowers system volume to 10% or less.") {
                    Picker("While recording", selection: $dimSystemAudio) {
                        Text("Do nothing").tag(false)
                        Text("Dim audio").tag(true)
                    }
                    .labelsHidden()
                    .frame(width: 180, alignment: .trailing)
                }
            }
        }
    }

    private var appearancePane: some View {
        VStack(alignment: .leading, spacing: 26) {
            section("Indicator") {
                ReviewIndicatorPlacement(
                    style: appearanceStyle,
                    customHex: usesCustomTint ? customTintHex : nil,
                    tint: tint,
                    onStyleChanged: { selectedStyle in
                        overlayStyle = selectedStyle.rawValue
                        (NSApp.delegate as? AppDelegate)?.refreshOverlay()
                    }
                ) { (NSApp.delegate as? AppDelegate)?.refreshIndicatorPlacement() }
                .id(appearanceStyle)
                settingRow("Indicator color", detail: "Colors the crab and recording indicator.") {
                    ReviewIndicatorColorPicker(
                        variant: $crabColorVariant,
                        customHex: $customTintHex,
                        usesCustomTint: $usesCustomTint,
                        tint: tint
                    ) {
                        (NSApp.delegate as? AppDelegate)?.refreshOverlay()
                    }
                }
            }
        }
    }

    private var appearanceStyle: OverlayStyle {
        guard let style = OverlayStyle(rawValue: overlayStyle), style != .off else { return .crab }
        return style
    }

    private var systemPane: some View {
        VStack(alignment: .leading, spacing: 26) {
            section("Startup") {
                settingRow("Launch at login") {
                    Toggle("Launch at login", isOn: Binding(
                        get: { launchAtLogin ?? false },
                        set: { enabled in
                            do {
                                if enabled { try SMAppService.mainApp.register() }
                                else { try SMAppService.mainApp.unregister() }
                                launchAtLogin = SMAppService.mainApp.status == .enabled
                            } catch {
                                launchAtLogin = SMAppService.mainApp.status == .enabled
                                errorMessage = error.localizedDescription
                            }
                        }
                    ))
                    .labelsHidden()
                    .disabled(launchAtLogin == nil)
                }
                Divider().overlay(ReviewTheme.line)
                settingRow("Show in Dock") {
                    Toggle("Show in Dock", isOn: Binding(
                        get: { showInDock },
                        set: { enabled in
                            showInDock = enabled
                            NSApp.setActivationPolicy(enabled ? .regular : .accessory)
                        }
                    ))
                    .labelsHidden()
                }
            }

            section("Permissions") {
                Text("ShoutOut uses these permissions to record your voice, detect the shortcut, and paste text.")
                    .font(.system(size: 13))
                    .foregroundStyle(ReviewTheme.muted)
                permissionRow("Microphone", granted: permissions.hasMicrophone) {
                    Task { await permissions.requestMicrophone() }
                }
                if transcription.selectedBackend.requiresSpeechRecognitionPermission {
                    permissionRow("Speech Recognition", granted: permissions.hasSpeechRecognition) {
                        Task { await permissions.requestSpeechRecognition() }
                    }
                }
                permissionRow("Accessibility", granted: permissions.hasAccessibility) {
                    permissions.requestAccessibility()
                }
                permissionRow("Input Monitoring", granted: permissions.hasInputMonitoring) {
                    permissions.requestInputMonitoring()
                }
                HStack(spacing: 10) {
                    if !permissions.missingPermissionNames.isEmpty {
                        Button("Open permission settings") {
                            permissions.openFirstMissingPermissionPane()
                        }
                    }
                    Button("Refresh status") { permissions.refresh() }
                }
                .buttonStyle(.bordered)
                .tint(ReviewTheme.text)
            }

            section("Local data") {
                settingRow("Transcription history", detail: "Saved only on this Mac.") {
                    HStack(spacing: 8) {
                        Button("Export…") { exportHistory() }
                        Button("Clear…") { confirmsHistoryClear = true }
                            .disabled(history.entries.isEmpty)
                    }
                    .buttonStyle(.bordered)
                    .tint(ReviewTheme.text)
                }
                settingRow("Usage stats", detail: "Word counts, dictations, and activity patterns.") {
                    ReviewClearUsageStatsButton(store: getUsageStats()) { confirmsStatsClear = true }
                }
            }

            section("About") {
                settingRow("ShoutOut", detail: AppVersionInfo.display) {
                    Button("Check for updates") {
                        (NSApp.delegate as? AppDelegate)?.checkForUpdates()
                    }
                    .buttonStyle(.bordered)
                    .tint(ReviewTheme.text)
                }
                settingRow("Help & diagnostics") {
                    Menu("Open") {
                        Button("Export diagnostics…") { exportDiagnostics() }
                        Button("Copy version information") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(AppVersionInfo.diagnosticsSummary, forType: .string)
                        }
                        Button("Show runtime log") {
                            NSWorkspace.shared.activateFileViewerSelecting([RuntimeLog.logURL])
                        }
                        Button("Show model files") { showModelFiles() }
                    }
                    .frame(width: 180, alignment: .trailing)
                }
            }
        }
        .task {
            launchAtLogin = nil
            permissions.refresh()
            let enabled = await Task.detached(priority: .userInitiated) {
                SMAppService.mainApp.status == .enabled
            }.value
            guard !Task.isCancelled else { return }
            launchAtLogin = enabled
        }
    }

    private func permissionRow(_ title: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(granted ? tint : ReviewTheme.muted)
            Text(title).font(.system(size: 13))
            Spacer()
            Text(granted ? "Granted" : "Needed")
                .font(.system(size: 13))
                .foregroundStyle(ReviewTheme.muted)
            if !granted {
                Button("Grant", action: action)
                    .buttonStyle(.bordered)
                    .tint(ReviewTheme.text)
            }
        }
        .padding(.vertical, 5)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
            Rectangle().fill(ReviewTheme.line).frame(height: 1)
            content()
        }
    }

    private func settingRow<Control: View>(
        _ title: String,
        detail: String? = nil,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 15, weight: .medium))
                if let detail {
                    Text(detail)
                        .font(.system(size: 13))
                        .foregroundStyle(ReviewTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            control()
                .frame(width: 180, alignment: .trailing)
        }
        .frame(maxWidth: .infinity)
    }

    private func showModelFiles() {
        let directory = TranscriptionService.modelsDirectory
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            errorMessage = "No model files yet. They’re downloaded the first time you dictate."
            return
        }
        if !NSWorkspace.shared.open(directory) {
            errorMessage = "Finder could not open the model folder at \(directory.path)."
        }
    }

    private func exportHistory() {
        let panel = NSSavePanel()
        panel.title = "Export Transcription History"
        panel.nameFieldStringValue = "ShoutOut History.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(history.recentEntries).write(to: url, options: .atomic)
        } catch {
            errorMessage = error.localizedDescription
        }
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
            errorMessage = error.localizedDescription
        }
    }
}

private struct ReviewClearUsageStatsButton: View {
    @ObservedObject var store: UsageStatsStore
    let action: () -> Void

    var body: some View {
        Button("Clear…", action: action)
            .buttonStyle(.bordered)
            .tint(ReviewTheme.text)
            .disabled(store.sessions.isEmpty)
            .accessibilityLabel("Clear usage stats…")
    }
}
