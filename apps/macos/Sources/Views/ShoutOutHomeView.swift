import AppKit
import ServiceManagement
import ShoutOutCore
import SwiftUI

enum ShoutOutHomeSection: String, CaseIterable, Identifiable {
    case dashboard
    case history
    case permissions
    case settings
    case insights

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .history: return "History"
        case .permissions: return "Permissions"
        case .settings: return "Settings"
        case .insights: return "Insights"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: return "rectangle.grid.2x2"
        case .history: return "clock.arrow.circlepath"
        case .permissions: return "checklist.checked"
        case .settings: return "slider.horizontal.3"
        case .insights: return "chart.bar"
        }
    }
}

@MainActor
final class ShoutOutHomeWindowModel: ObservableObject {
    @Published var selectedSection: ShoutOutHomeSection = .dashboard
}

struct ShoutOutHomeView: View {
    @EnvironmentObject var transcription: TranscriptionService
    @EnvironmentObject var languagePass: LanguagePassService
    @EnvironmentObject var permissions: PermissionManager
    @EnvironmentObject var usageStats: UsageStatsStore
    @EnvironmentObject var transcriptionHistory: TranscriptionHistoryStore
    @ObservedObject var model: ShoutOutHomeWindowModel
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
    @State private var isConfirmingHistoryClear = false
    @State private var advancedSettingsExpanded = false

    var body: some View {
        HomeWindowShell {
            sidebar
        } content: {
            content
        }
        .frame(minWidth: 820, idealWidth: 1240, minHeight: 620, idealHeight: 760)
        .background(boringMode ? ShoutOutHomeTheme.boringBackground : ShoutOutHomeTheme.background)
        .foregroundStyle(ShoutOutHomeTheme.ink)
        .modifier(HomeBoringModeVisual(isEnabled: boringMode))
        .animation(.easeInOut(duration: 0.18), value: boringMode)
        .onChange(of: boringMode) { _, newValue in
            overlayStyle = newValue ? OverlayStyle.capsule.rawValue : OverlayStyle.crab.rawValue
            (NSApp.delegate as? AppDelegate)?.refreshOverlay()
        }
        .alert("Clear local stats?", isPresented: $isConfirmingStatsClear) {
            Button("Clear Stats", role: .destructive) {
                try? usageStats.clear()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes your local word counts, sessions, and latency history from this Mac.")
        }
        .alert("Clear transcription history?", isPresented: $isConfirmingHistoryClear) {
            Button("Clear History", role: .destructive) {
                try? transcriptionHistory.clear()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes saved transcript text from this Mac. Usage stats stay intact.")
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                HomeBrandMark()

                Text("local Mac dictation")
                    .font(.system(.caption, design: .monospaced).weight(.semibold))
                    .foregroundStyle(ShoutOutHomeTheme.muted)
            }

            VStack(spacing: 8) {
                ForEach(ShoutOutHomeSection.allCases) { section in
                    Button {
                        model.selectedSection = section
                    } label: {
                        Label(section.title, systemImage: section.systemImage)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(HomeSidebarButtonStyle(isSelected: model.selectedSection == section))
                }
            }

            Spacer()

            HomeStatusBadge(
                title: "Shortcut",
                value: selectedHotkeyTrigger.displayName,
                systemImage: "keyboard"
            )

            HomeStatusBadge(
                title: "Mode",
                value: transcription.selectedPreset.title,
                systemImage: "waveform.path.ecg"
            )
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(ShoutOutHomeTheme.sidebar)
    }

    @ViewBuilder
    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                switch model.selectedSection {
                case .dashboard:
                    dashboardPage
                case .history:
                    historyPage
                case .permissions:
                    permissionsPage
                case .settings:
                    settingsPage
                case .insights:
                    insightsPage
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
    }

    private var dashboardPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            HomeHeroPanel(
                modelStateText: modelStatusText,
                permissionText: permissions.statusText,
                todayWordCount: usageStats.todaySummary.wordCount,
                hotkeyName: selectedHotkeyTrigger.displayName
            )

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 14)], spacing: 14) {
                MetricTile(
                    title: "Today",
                    value: "\(usageStats.todaySummary.wordCount)",
                    caption: "words captured",
                    color: ShoutOutHomeTheme.panelBlue
                )
                MetricTile(
                    title: "All Time",
                    value: "\(usageStats.allTimeSummary.sessionCount)",
                    caption: "dictation sessions",
                    color: ShoutOutHomeTheme.panelMint
                )
                MetricTile(
                    title: "Mode",
                    value: transcription.selectedPreset.title,
                    caption: "dictation preset",
                    color: ShoutOutHomeTheme.panelLilac
                )
            }

            HStack(spacing: 14) {
                ActionPanel(
                    title: "Setup",
                    message: permissions.missingPermissionNames.isEmpty
                        ? "All required permissions are currently available."
                        : "\(permissions.missingPermissionNames.count) permission step needs attention.",
                    buttonTitle: "Review",
                    systemImage: "checkmark.seal"
                ) {
                    model.selectedSection = .permissions
                }

                ActionPanel(
                    title: "Tuning",
                    message: "Choose the dictation mode, writing style, indicator, and crab color.",
                    buttonTitle: "Open",
                    systemImage: "paintpalette"
                ) {
                    model.selectedSection = .settings
                }
            }
        }
    }

    private var permissionsPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageHeader(
                title: "Permissions",
                subtitle: "macOS keeps these switches explicit. ShoutOut stays useful once they are granted."
            )

            VStack(spacing: 10) {
                PermissionChecklistRow(
                    title: "Microphone",
                    detail: "Records your voice locally.",
                    systemImage: "mic",
                    isGranted: permissions.hasMicrophone,
                    actionTitle: "Grant"
                ) {
                    Task { await permissions.requestMicrophone() }
                }

                if transcription.selectedBackend.requiresSpeechRecognitionPermission {
                    PermissionChecklistRow(
                        title: "Speech Recognition",
                        detail: "Required for Apple Speech engines.",
                        systemImage: "waveform",
                        isGranted: permissions.hasSpeechRecognition,
                        actionTitle: "Grant"
                    ) {
                        Task { await permissions.requestSpeechRecognition() }
                    }
                }

                PermissionChecklistRow(
                    title: "Accessibility",
                    detail: "Lets ShoutOut paste into focused fields.",
                    systemImage: "hand.raised",
                    isGranted: permissions.hasAccessibility,
                    actionTitle: "Grant"
                ) {
                    permissions.requestAccessibility()
                }

                PermissionChecklistRow(
                    title: "Input Monitoring",
                    detail: "Lets the global shortcut work outside the app.",
                    systemImage: "keyboard",
                    isGranted: permissions.hasInputMonitoring,
                    actionTitle: "Grant"
                ) {
                    permissions.requestInputMonitoring()
                }
            }

            HStack {
                Button("Open Missing") {
                    permissions.openFirstMissingPermissionPane()
                }
                .buttonStyle(HomePrimaryButtonStyle())
                .disabled(permissions.missingPermissionNames.isEmpty)

                Button("Refresh") {
                    permissions.refresh()
                }
                .buttonStyle(HomeSecondaryButtonStyle())
            }
        }
    }

    private var historyPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageHeader(
                title: "History",
                subtitle: "Recent local transcriptions saved on this Mac."
            )

            if transcriptionHistory.recentEntries.isEmpty {
                HomePanel {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("No transcriptions yet", systemImage: "text.badge.plus")
                            .font(.headline)
                        Text("Your pasted dictations will show up here after ShoutOut captures text.")
                            .foregroundStyle(ShoutOutHomeTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                VStack(spacing: 12) {
                    ForEach(transcriptionHistory.recentEntries) { entry in
                        TranscriptionHistoryRow(entry: entry)
                    }
                }

                Button("Clear History", role: .destructive) {
                    isConfirmingHistoryClear = true
                }
                .buttonStyle(HomeSecondaryButtonStyle())
            }
        }
    }

    private var settingsPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageHeader(
                title: "Settings",
                subtitle: "Tune the shortcut, mascot, dictation mode, and writing style without leaving the dashboard."
            )

            HStack(alignment: .top, spacing: HomeSettingsLayout.gap) {
                settingsPrimaryColumn
                settingsSecondaryColumn
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var settingsPrimaryColumn: some View {
        VStack(spacing: HomeSettingsLayout.gap) {
            shortcutSettingsCard
            transcriptionSettingsCard
            textSettingsCard
            generalSettingsCard
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .top)
    }

    private var settingsSecondaryColumn: some View {
        VStack(spacing: HomeSettingsLayout.gap) {
            indicatorSettingsCard
            advancedSettingsCard
            filesSettingsCard
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .top)
    }

    private var shortcutSettingsCard: some View {
        HomeSettingSection(
            title: "Shortcut",
            subtitle: "Choose what starts and stops dictation.",
            systemImage: "keyboard",
            minHeight: HomeSettingsLayout.shortCardHeight
        ) {
            HomeControlRow(
                title: "Trigger",
                detail: selectedHotkeyTrigger.detailText,
                systemImage: "keyboard"
            ) {
                HomeStringMenu(
                    selection: $hotkeyTrigger,
                    choices: HotkeyTrigger.allCases.map {
                        HomeStringChoice(value: $0.rawValue, title: $0.displayName)
                    },
                    width: 170
                ) {
                    (NSApp.delegate as? AppDelegate)?.restartHotkey()
                }
            }

            HomeStatusLine(
                title: "Modes",
                value: "Hold, or double tap",
                systemImage: "hand.tap",
                color: ShoutOutHomeTheme.ink
            )
        }
    }

    private var indicatorSettingsCard: some View {
        HomeSettingSection(
            title: "Indicator",
            subtitle: "The little guy that lives at the screen edge.",
            systemImage: "macwindow.on.rectangle",
            minHeight: HomeSettingsLayout.shortCardHeight
        ) {
            HomeToggleRow(title: "Boring mode", systemImage: "rectangle.dashed", isOn: $boringMode)

            HomeControlRow(title: "Style", systemImage: "sparkles") {
                HomeStringMenu(
                    selection: $overlayStyle,
                    choices: [
                        HomeStringChoice(value: OverlayStyle.crab.rawValue, title: "Crab"),
                        HomeStringChoice(value: OverlayStyle.capsule.rawValue, title: "Classic"),
                        HomeStringChoice(value: OverlayStyle.off.rawValue, title: "Off"),
                    ],
                    width: 140,
                    isDisabled: boringMode
                ) {
                    (NSApp.delegate as? AppDelegate)?.refreshOverlay()
                }
            }

            HomeControlRow(title: "Crab color", systemImage: "paintpalette") {
                HomeCrabColorMenu(
                    selection: $crabColorVariant,
                    width: 176,
                    isDisabled: boringMode || overlayStyle != OverlayStyle.crab.rawValue
                ) {
                    (NSApp.delegate as? AppDelegate)?.refreshOverlay()
                }
            }
        }
    }

    private var transcriptionSettingsCard: some View {
        HomeSettingSection(
            title: "Dictation",
            subtitle: transcription.selectedPreset.detail,
            systemImage: "waveform.path.ecg",
            minHeight: HomeSettingsLayout.shortCardHeight
        ) {
            HomeControlRow(
                title: "Mode",
                detail: dictationPresetDetail,
                systemImage: "cpu"
            ) {
                HomeStringMenu(
                    selection: dictationPresetValueBinding,
                    choices: DictationPreset.allCases.map {
                        HomeStringChoice(value: $0.rawValue, title: $0.title, subtitle: $0.detail)
                    },
                    width: 270
                ) {}
            }

            HomeStatusLine(
                title: "Status",
                value: modelStatusText,
                systemImage: "circle.fill",
                color: modelStatusColor
            )
        }
    }

    private var textSettingsCard: some View {
        HomeSettingSection(
            title: "Writing",
            subtitle: "Pick how cleaned-up dictation should read.",
            systemImage: "text.cursor",
            minHeight: HomeSettingsLayout.shortCardHeight
        ) {
            HomeControlRow(
                title: "Writing style",
                detail: languagePass.selectedStyle.detail,
                systemImage: "text.quote"
            ) {
                HomeStringMenu(
                    selection: languagePassStyleBinding,
                    choices: LanguagePassStyle.allCases.map {
                        HomeStringChoice(value: $0.rawValue, title: $0.title, subtitle: $0.detail)
                    },
                    width: 270
                ) {}
            }
            HomeStatusLine(
                title: "Cleanup",
                value: languagePassStatusText,
                systemImage: "circle.fill",
                color: languagePassStatusColor
            )
            if let progress = languagePass.modelState.startupProgress,
                languagePass.isEnabled,
                !languagePass.modelState.isReady
            {
                VStack(alignment: .leading, spacing: 6) {
                    ModelProgressBar(progress: progress, height: 7)
                    Text(languagePassProgressCaption)
                        .font(.system(.caption, design: .monospaced).weight(.bold))
                        .foregroundStyle(ShoutOutHomeTheme.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(ShoutOutHomeTheme.panelBlue.opacity(0.45))
                .overlay(ShoutOutHomeTheme.pixelBorder)
            }
            if let summary = languagePass.lastRunSummary {
                HomeStatusLine(
                    title: "Last cleanup",
                    value: languagePassSummaryText(summary),
                    systemImage: "timer",
                    color: ShoutOutHomeTheme.teal
                )
            }
        }
    }

    private var advancedSettingsCard: some View {
        HomeSettingSection(
            title: "Advanced",
            subtitle: "Exact controls for debugging, unusual Macs, and support.",
            systemImage: "wrench.adjustable",
            minHeight: advancedSettingsExpanded ? HomeSettingsLayout.tallCardHeight : HomeSettingsLayout.shortCardHeight
        ) {
            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    advancedSettingsExpanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: advancedSettingsExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.black))
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(advancedSettingsExpanded ? "Hide exact controls" : "Show exact controls")
                            .font(.headline)
                        Text("Engine, model, paste spacing, and cleanup toggles")
                            .font(.caption)
                            .foregroundStyle(ShoutOutHomeTheme.muted)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(ShoutOutHomeTheme.panelBlue.opacity(0.45))
                .overlay(ShoutOutHomeTheme.pixelBorder)
            }
            .buttonStyle(.plain)

            if advancedSettingsExpanded {
                HomeToggleRow(
                    title: "Language cleanup",
                    detail: "Runs the local cleanup model after transcription. If it is off, slow, or unsure, ShoutOut pastes the transcript without the LM pass.",
                    systemImage: "sparkles",
                    isOn: languagePassEnabledBinding
                )

                HomeControlRow(
                    title: "Engine",
                    detail: "Exact transcription backend. Presets are safer unless you are debugging permissions, startup, or device-specific behavior.",
                    systemImage: "waveform.path.ecg"
                ) {
                    HomeBackendMenu(
                        selection: $transcription.selectedBackend,
                        backends: transcription.availableBackends,
                        width: 160
                    ) {
                        permissions.refresh()
                        Task { await transcription.loadModel() }
                    }
                }

                if transcription.selectedBackend.requiresManagedModel {
                    HomeControlRow(
                        title: "Model",
                        detail: "\(TranscriptionModelOption.option(for: transcription.selectedModel).detail) Changing it unloads and prepares the selected model.",
                        systemImage: "internaldrive"
                    ) {
                        HomeStringMenu(
                            selection: $transcription.selectedModel,
                            choices: TranscriptionModelOption.all.map {
                                HomeStringChoice(value: $0.id, title: $0.title, subtitle: $0.detail)
                            },
                            width: 250
                        ) {
                            Task { await transcription.loadModel() }
                        }
                    }
                }

                HomeToggleRow(
                    title: "Remove filler words",
                    detail: "Removes simple filler like um, uh, and you know before the language cleanup pass.",
                    systemImage: "text.badge.minus",
                    isOn: $removeFillerWords
                )
                HomeToggleRow(
                    title: "Smart spacing",
                    detail: "Uses nearby cursor context to avoid extra spaces and keep mid-sentence insertions natural.",
                    systemImage: "text.alignleft",
                    isOn: $smartSpacing
                )
                HomeToggleRow(
                    title: "Fallback trailing space",
                    detail: "Adds a trailing space when ShoutOut cannot inspect the focused field's surrounding text.",
                    systemImage: "arrow.right.to.line",
                    isOn: $appendTrailingSpace
                )
            }
        }
    }

    private var generalSettingsCard: some View {
        HomeSettingSection(
            title: "General",
            subtitle: "How ShoutOut behaves as a Mac app.",
            systemImage: "gearshape",
            minHeight: HomeSettingsLayout.mediumCardHeight
        ) {
            HomeToggleRow(title: "Launch at login", systemImage: "arrow.right.circle", isOn: $launchAtLogin)
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

            HomeToggleRow(title: "Show in Dock", systemImage: "dock.rectangle", isOn: $showInDock)
                .onChange(of: showInDock) { _, _ in
                    (NSApp.delegate as? AppDelegate)?.applyDockVisibilityPreference()
                }

            HomeToggleRow(title: "Dim audio while recording", systemImage: "speaker.wave.1", isOn: $dimSystemAudio)

            HomeControlRow(
                title: "Version",
                detail: AppVersionInfo.builtAt.map { "Built \($0)" },
                systemImage: "number"
            ) {
                Button(AppVersionInfo.displayWithCommit) {
                    copyVersionInfo()
                }
                .buttonStyle(HomeSecondaryButtonStyle())
            }

            HomeControlRow(
                title: "Updates",
                detail: "\(AppUpdaterConfiguration.statusText) · \(AppUpdaterConfiguration.feedURLString)",
                systemImage: "arrow.triangle.2.circlepath"
            ) {
                Button("Check") {
                    (NSApp.delegate as? AppDelegate)?.checkForUpdates()
                }
                .buttonStyle(HomeSecondaryButtonStyle())
            }
        }
    }

    private var filesSettingsCard: some View {
        HomeSettingSection(
            title: "Files",
            subtitle: "Local model storage and runtime diagnostics.",
            systemImage: "folder",
            minHeight: HomeSettingsLayout.mediumCardHeight
        ) {
            HomeControlRow(title: "Models", detail: transcription.modelsDiskUsage, systemImage: "internaldrive") {
                Button("Show") {
                    NSWorkspace.shared.selectFile(
                        nil,
                        inFileViewerRootedAtPath: TranscriptionService.modelsDirectory.path
                    )
                }
                .buttonStyle(HomeSecondaryButtonStyle())
            }

            HomeControlRow(title: "Runtime log", detail: RuntimeLog.logURL.lastPathComponent, systemImage: "doc.text.magnifyingglass") {
                Button("Show") {
                    NSWorkspace.shared.selectFile(
                        RuntimeLog.logURL.path,
                        inFileViewerRootedAtPath: RuntimeLog.logURL.deletingLastPathComponent().path
                    )
                }
                .buttonStyle(HomeSecondaryButtonStyle())
            }

            HomeControlRow(title: "Diagnostics", detail: "Logs, build info, and crash reports", systemImage: "shippingbox") {
                Button("Export") {
                    exportDiagnostics()
                }
                .buttonStyle(HomeSecondaryButtonStyle())
            }
        }
    }

    private var insightsPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageHeader(
                title: "Insights",
                subtitle: "Your local dictation pace, streaks, and daily volume. No accounts required."
            )

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 14)], spacing: 14) {
                InsightMetricPanel(
                    title: "Current Streak",
                    value: "\(usageStats.insights.currentStreakDays)",
                    caption: dayCountText(usageStats.insights.currentStreakDays)
                )
                InsightMetricPanel(
                    title: "Best Day",
                    value: "\(usageStats.insights.bestDayWordCount)",
                    caption: "words"
                )
                InsightMetricPanel(
                    title: "Active Days",
                    value: "\(usageStats.insights.days.count)",
                    caption: dayCountText(usageStats.insights.days.count)
                )
                InsightMetricPanel(
                    title: "All-Time Pace",
                    value: "\(usageStats.allTimeSummary.averageWordsPerMinute)",
                    caption: "WPM"
                )
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 14)], spacing: 14) {
                UsageDailyBarChart(
                    title: "Words Per Day",
                    subtitle: "Last 14 active days",
                    days: Array(usageStats.insights.days.suffix(14)),
                    value: \.wordCount,
                    color: ShoutOutHomeTheme.coral
                )
                UsageDailyBarChart(
                    title: "Sessions Per Day",
                    subtitle: "Last 14 active days",
                    days: Array(usageStats.insights.days.suffix(14)),
                    value: \.sessionCount,
                    color: ShoutOutHomeTheme.teal
                )
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 14)], spacing: 14) {
                SummaryPanel(title: "Today", summary: usageStats.todaySummary)
                SummaryPanel(title: "All Time", summary: usageStats.allTimeSummary)
            }

            if let lastSession = usageStats.recentSessions.first {
                HomePanel {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Last Dictation", systemImage: "clock")
                            .font(.headline)
                        Text("\(lastSession.wordCount) words at \(lastSession.wordsPerMinute) WPM")
                            .foregroundStyle(ShoutOutHomeTheme.muted)
                    }
                }
            }

            Button("Clear Stats", role: .destructive) {
                isConfirmingStatsClear = true
            }
            .buttonStyle(HomeSecondaryButtonStyle())
            .disabled(usageStats.recentSessions.isEmpty)
        }
    }

    private func dayCountText(_ count: Int) -> String {
        count == 1 ? "day" : "days"
    }

    private var modelStatusText: String {
        switch transcription.modelState {
        case .ready: return "Ready"
        case .loading: return "Loading"
        case .downloading(let progress): return "Downloading \(Int(progress * 100))%"
        case .error: return "Needs attention"
        case .unloaded: return "Not loaded"
        }
    }

    private var modelStatusColor: Color {
        switch transcription.modelState {
        case .ready: return .green
        case .loading, .downloading: return .orange
        case .error: return .red
        case .unloaded: return ShoutOutHomeTheme.muted
        }
    }

    private var dictationPresetDetail: String {
        switch transcription.selectedPreset {
        case .best:
            return "Highest quality"
        case .fast:
            return "Lower latency"
        case .system:
            return "No download"
        }
    }

    private var dictationPresetValueBinding: Binding<String> {
        Binding(
            get: { transcription.selectedPreset.rawValue },
            set: { value in
                applyDictationPreset(DictationPreset(rawValue: value) ?? .best)
            }
        )
    }

    private func applyDictationPreset(_ preset: DictationPreset) {
        transcription.applyPreset(preset)
        languagePass.isEnabled = true
        permissions.refresh()
        Task {
            await transcription.loadModel()
            await languagePass.prepareIfNeeded()
        }
    }

    private var languagePassEnabledBinding: Binding<Bool> {
        Binding(
            get: { languagePass.isEnabled },
            set: { languagePass.isEnabled = $0 }
        )
    }

    private var languagePassStyleBinding: Binding<String> {
        Binding(
            get: { languagePass.selectedStyle.rawValue },
            set: { languagePass.selectedStyle = LanguagePassStyle(storedValue: $0) }
        )
    }

    private var languagePassStatusText: String {
        guard languagePass.isEnabled else {
            return "Off"
        }
        switch languagePass.modelState {
        case .ready:
            return "Ready"
        case .loading:
            return "Loading"
        case .downloading(let progress):
            return "Downloading \(Int(progress * 100))%"
        case .error:
            return "Needs attention"
        case .unloaded:
            return "Not loaded"
        }
    }

    private var languagePassStatusColor: Color {
        guard languagePass.isEnabled else {
            return ShoutOutHomeTheme.muted
        }
        switch languagePass.modelState {
        case .ready: return .green
        case .loading, .downloading: return .orange
        case .error: return .red
        case .unloaded: return ShoutOutHomeTheme.muted
        }
    }

    private var languagePassProgressCaption: String {
        switch languagePass.modelState {
        case .downloading(let progress):
            return "Downloading \(Int(progress * 100))% of the local cleanup model"
        case .loading:
            return "Preparing language cleanup"
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

    private var selectedHotkeyTrigger: HotkeyTrigger {
        HotkeyTrigger(rawValue: hotkeyTrigger) ?? .defaultTrigger
    }

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
}

private enum ShoutOutHomeTheme {
    static let ink = Color(red: 0.03, green: 0.09, blue: 0.18)
    static let muted = Color(red: 0.25, green: 0.33, blue: 0.46)
    static let background = Color(red: 0.78, green: 0.87, blue: 0.97)
    static let boringBackground = Color(red: 0.86, green: 0.88, blue: 0.91)
    static let sidebar = Color(red: 0.84, green: 0.93, blue: 0.99)
    static let panel = Color(red: 0.97, green: 0.99, blue: 1.00)
    static let panelBlue = Color(red: 0.66, green: 0.84, blue: 1.00)
    static let panelMint = Color(red: 0.56, green: 0.85, blue: 0.86)
    static let panelLilac = Color(red: 0.75, green: 0.82, blue: 1.00)
    static let coral = Color(red: 1.00, green: 0.44, blue: 0.41)
    static let teal = Color(red: 0.08, green: 0.59, blue: 0.68)

    static var pixelBorder: some View {
        Rectangle()
            .stroke(ink, lineWidth: 2)
    }
}

private struct HomeBoringModeVisual: ViewModifier {
    let isEnabled: Bool

    func body(content: Content) -> some View {
        content
            .saturation(isEnabled ? 0.12 : 1)
            .contrast(isEnabled ? 0.92 : 1)
            .brightness(isEnabled ? -0.01 : 0)
    }
}

private enum HomeWindowLayout {
    static let sidebarWidth: CGFloat = 250
}

private enum HomeSettingsLayout {
    static let gap: CGFloat = 14
    static let columnMinWidth: CGFloat = 420
    static let shortCardHeight: CGFloat = 178
    static let tallCardHeight: CGFloat = 0
    static let mediumCardHeight: CGFloat = 0
}

private struct HomeWindowShell<Sidebar: View, Content: View>: View {
    @ViewBuilder let sidebar: Sidebar
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: HomeWindowLayout.sidebarWidth, alignment: .topLeading)
                .frame(maxHeight: .infinity, alignment: .topLeading)

            Divider()
                .overlay(ShoutOutHomeTheme.ink.opacity(0.55))

            content
                .frame(
                    minWidth: 0,
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: .topLeading
                )
                .layoutPriority(1)
        }
    }
}

private struct HomeBrandMark: View {
    @AppStorage(Defaults.crabColorVariant) private var crabColorVariant = CrabColorVariant.ocean.rawValue

    var body: some View {
        HStack(spacing: 7) {
            if let image = NSImage.crabVariantSprite(named: "idle-1", variant: colorVariant) {
                Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28, height: 24)
            }

            Text("ShoutOut")
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 3)
        .pixelBox(
            background: ShoutOutHomeTheme.panelBlue,
            shadow: ShoutOutHomeTheme.teal,
            shadowOffset: CGSize(width: 4, height: 4)
        )
    }

    private var colorVariant: CrabColorVariant {
        CrabColorVariant(rawValue: crabColorVariant) ?? .ocean
    }
}

private struct HomeHeroPanel: View {
    let modelStateText: String
    let permissionText: String
    let todayWordCount: Int
    let hotkeyName: String

    var body: some View {
        HomePanel(background: ShoutOutHomeTheme.panel) {
            HStack(alignment: .center, spacing: 22) {
                VStack(alignment: .leading, spacing: 14) {
                Text("Ready when your cursor is.")
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)

                    Text("Hold \(hotkeyName), talk, and ShoutOut drops text into the app you were already using.")
                        .font(.body.weight(.medium))
                        .foregroundStyle(ShoutOutHomeTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(alignment: .top, spacing: 10) {
                        HeroChip(title: "Dictation", value: modelStateText)
                        HeroChip(title: "Setup", value: permissionText)
                        HeroChip(title: "Today", value: "\(todayWordCount) words")
                    }
                }

                Spacer(minLength: 8)

                MascotPreview()
            }
        }
    }
}

private struct MascotPreview: View {
    @AppStorage(Defaults.crabColorVariant) private var crabColorVariant = CrabColorVariant.ocean.rawValue

    var body: some View {
        ZStack {
            Rectangle()
                .fill(ShoutOutHomeTheme.panelBlue)
                .overlay(ShoutOutHomeTheme.pixelBorder)

            if let image = NSImage.crabVariantSprite(named: "idle-1", variant: colorVariant) {
                Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 112, height: 112)
            } else {
                Image(systemName: "waveform")
                    .font(.system(size: 48, weight: .bold))
            }
        }
        .pixelBoxShadow(color: ShoutOutHomeTheme.coral, offset: CGSize(width: 7, height: 7))
        .frame(width: 150, height: 150)
    }

    private var colorVariant: CrabColorVariant {
        CrabColorVariant(rawValue: crabColorVariant) ?? .ocean
    }
}

private struct HeroChip: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(ShoutOutHomeTheme.muted)
            Text(value)
                .font(.system(.caption, design: .monospaced).weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(minWidth: 82, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(ShoutOutHomeTheme.panelBlue)
        .overlay(ShoutOutHomeTheme.pixelBorder)
    }
}

private struct PageHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 34, weight: .heavy, design: .rounded))
            Text(subtitle)
                .font(.body.weight(.medium))
                .foregroundStyle(ShoutOutHomeTheme.muted)
        }
        .frame(maxWidth: 680, alignment: .leading)
    }
}

private struct HomePanel<Content: View>: View {
    var background = ShoutOutHomeTheme.panel
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .pixelBox(
                background: background,
                shadow: ShoutOutHomeTheme.ink,
                shadowOffset: CGSize(width: 5, height: 5)
            )
    }
}

private struct HomeSettingSection<Content: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    var minHeight: CGFloat = 0
    @ViewBuilder var content: Content

    var body: some View {
        HomePanel {
            VStack(alignment: .leading, spacing: 14) {
                Label(title, systemImage: systemImage)
                    .font(.system(.title3, design: .rounded).weight(.heavy))
                Text(subtitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ShoutOutHomeTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(spacing: 10) {
                    content
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(
                maxWidth: .infinity,
                minHeight: max(0, minHeight - 36),
                alignment: .topLeading
            )
        }
    }
}

private struct HomeControlRow<Accessory: View>: View {
    let title: String
    var detail: String?
    let systemImage: String
    @ViewBuilder var accessory: Accessory

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    controlLabel
                        .layoutPriority(3)

                    Spacer(minLength: 8)
                    accessory
                        .layoutPriority(1)
                }

                VStack(alignment: .leading, spacing: 8) {
                    controlLabel
                    accessory
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(ShoutOutHomeTheme.muted)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(ShoutOutHomeTheme.panelBlue.opacity(0.45))
        .overlay(ShoutOutHomeTheme.pixelBorder)
    }

    private var controlLabel: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .frame(width: 22)
            Text(title)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

private struct HomeCrabColorMenuLabel: View {
    let variant: CrabColorVariant
    let isOpen: Bool
    let width: CGFloat

    var body: some View {
        HStack(spacing: 8) {
            ColorPreviewTile(color: variant.swatchColor, width: 30, height: 18)

            Text(variant.displayName)
                .font(.system(.caption, design: .monospaced).weight(.heavy))
                .foregroundStyle(ShoutOutHomeTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Spacer(minLength: 6)

            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(isOpen ? ShoutOutHomeTheme.coral : ShoutOutHomeTheme.ink)
        }
        .frame(width: width)
        .frame(minHeight: 28)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(ShoutOutHomeTheme.panel)
        .overlay(ShoutOutHomeTheme.pixelBorder)
    }
}

private struct HomeCrabColorMenu: View {
    @Binding var selection: String
    let width: CGFloat
    var isDisabled = false
    let onChange: () -> Void
    @State private var isOpen = false

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
    ]

    var body: some View {
        Button {
            guard !isDisabled else { return }
            isOpen.toggle()
        } label: {
            HomeCrabColorMenuLabel(variant: selectedVariant, isOpen: isOpen, width: width)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.55 : 1)
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            HomeMenuPopover(width: 388) {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                    ForEach(CrabColorVariant.allCases) { variant in
                        HomeCrabColorOption(
                            variant: variant,
                            isSelected: variant.rawValue == selection
                        ) {
                            selection = variant.rawValue
                            isOpen = false
                            onChange()
                        }
                    }
                }
            }
        }
    }

    private var selectedVariant: CrabColorVariant {
        CrabColorVariant(rawValue: selection) ?? .ocean
    }
}

private struct HomeCrabColorOption: View {
    let variant: CrabColorVariant
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                ColorPreviewTile(color: variant.swatchColor, width: 34, height: 24)

                Text(variant.displayName)
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .foregroundStyle(ShoutOutHomeTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)

                Spacer(minLength: 4)

                Image(systemName: isSelected ? "checkmark" : "arrow.right")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(isSelected ? ShoutOutHomeTheme.coral : ShoutOutHomeTheme.muted.opacity(isHovered ? 0.75 : 0))
                    .frame(width: 14)
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(rowBackground)
            .overlay {
                Rectangle()
                    .stroke(rowBorder, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }

    private var rowBackground: Color {
        if isSelected {
            return ShoutOutHomeTheme.panelBlue.opacity(0.62)
        }
        if isHovered {
            return ShoutOutHomeTheme.panelBlue.opacity(0.34)
        }
        return .clear
    }

    private var rowBorder: Color {
        if isSelected {
            return ShoutOutHomeTheme.ink
        }
        if isHovered {
            return ShoutOutHomeTheme.coral.opacity(0.75)
        }
        return .clear
    }
}

private struct ColorPreviewTile: View {
    let color: Color
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        Rectangle()
            .fill(color)
            .frame(width: width, height: height)
            .overlay {
                Rectangle()
                    .stroke(ShoutOutHomeTheme.ink.opacity(0.75), lineWidth: 1)
            }
            .overlay(alignment: .topLeading) {
                Rectangle()
                    .fill(.white.opacity(0.20))
                    .frame(height: max(3, height * 0.28))
            }
    }
}

private struct HomeStringChoice: Identifiable {
    let value: String
    let title: String
    var subtitle: String?

    var id: String { value }
}

private struct HomeStringMenu: View {
    @Binding var selection: String
    let choices: [HomeStringChoice]
    var width: CGFloat
    var isDisabled = false
    let onChange: () -> Void
    @State private var isOpen = false

    var body: some View {
        Button {
            guard !isDisabled else { return }
            isOpen.toggle()
        } label: {
            HomeMenuLabel(
                title: selectedChoice.title,
                subtitle: selectedChoice.subtitle,
                width: width,
                isOpen: isOpen
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.55 : 1)
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            HomeMenuPopover(width: max(width + 90, 320)) {
                ForEach(choices) { choice in
                    HomeMenuOption(
                        title: choice.title,
                        subtitle: choice.subtitle,
                        isSelected: choice.value == selection
                    ) {
                        selection = choice.value
                        isOpen = false
                        onChange()
                    }
                }
            }
        }
    }

    private var selectedChoice: HomeStringChoice {
        choices.first { $0.value == selection }
            ?? choices.first
            ?? HomeStringChoice(value: "", title: "Choose")
    }
}

private struct HomeBackendMenu: View {
    @Binding var selection: TranscriptionBackend
    let backends: [TranscriptionBackend]
    var width: CGFloat
    let onChange: () -> Void
    @State private var isOpen = false

    var body: some View {
        Button {
            isOpen.toggle()
        } label: {
            HomeMenuLabel(title: selection.displayName, subtitle: nil, width: width, isOpen: isOpen)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            HomeMenuPopover(width: width + 210) {
                ForEach(backends) { backend in
                    HomeMenuOption(
                        title: backend.displayName,
                        subtitle: backend.detailText,
                        isSelected: backend == selection
                    ) {
                        selection = backend
                        isOpen = false
                        onChange()
                    }
                }
            }
        }
    }
}

private struct HomeMenuLabel: View {
    let title: String
    var subtitle: String?
    let width: CGFloat
    let isOpen: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.caption, design: .monospaced).weight(.heavy))
                    .foregroundStyle(ShoutOutHomeTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(ShoutOutHomeTheme.muted)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(isOpen ? ShoutOutHomeTheme.coral : ShoutOutHomeTheme.ink)
        }
        .frame(width: width, alignment: .leading)
        .frame(minHeight: subtitle == nil ? 28 : 48)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(ShoutOutHomeTheme.panel)
        .overlay(ShoutOutHomeTheme.pixelBorder)
    }
}

private struct HomeMenuPopover<Content: View>: View {
    let width: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            content
        }
        .padding(8)
        .frame(width: width, alignment: .leading)
        .background(ShoutOutHomeTheme.panel)
    }
}

private struct HomeMenuOption: View {
    let title: String
    var subtitle: String?
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(.caption, design: .monospaced).weight(.heavy))
                        .foregroundStyle(ShoutOutHomeTheme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(ShoutOutHomeTheme.muted)
                            .lineLimit(2)
                            .minimumScaleFactor(0.65)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 8)

                Image(systemName: isSelected ? "checkmark" : "arrow.right")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(isSelected ? ShoutOutHomeTheme.coral : ShoutOutHomeTheme.muted.opacity(isHovered ? 0.75 : 0))
                    .frame(width: 16)
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(rowBackground)
            .overlay {
                Rectangle()
                    .stroke(rowBorder, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }

    private var rowBackground: Color {
        if isSelected {
            return ShoutOutHomeTheme.panelBlue.opacity(0.62)
        }
        if isHovered {
            return ShoutOutHomeTheme.panelBlue.opacity(0.34)
        }
        return .clear
    }

    private var rowBorder: Color {
        if isSelected {
            return ShoutOutHomeTheme.ink
        }
        if isHovered {
            return ShoutOutHomeTheme.coral.opacity(0.75)
        }
        return .clear
    }
}

private struct HomeToggleRow: View {
    let title: String
    var detail: String?
    let systemImage: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 4) {
                Label(title, systemImage: systemImage)
                    .font(.headline)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(ShoutOutHomeTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .toggleStyle(.switch)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(ShoutOutHomeTheme.panelBlue.opacity(0.45))
        .overlay(ShoutOutHomeTheme.pixelBorder)
    }
}

private struct HomeStatusLine: View {
    let title: String
    let value: String
    let systemImage: String
    let color: Color

    var body: some View {
        HStack {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(color)
            Spacer()
            Text(value)
                .font(.system(.caption, design: .monospaced).weight(.heavy))
                .foregroundStyle(ShoutOutHomeTheme.muted)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(ShoutOutHomeTheme.panelBlue.opacity(0.45))
        .overlay(ShoutOutHomeTheme.pixelBorder)
    }
}

private struct MetricTile: View {
    let title: String
    let value: String
    let caption: String
    let color: Color

    var body: some View {
        HomePanel(background: color) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title.uppercased())
                    .font(.system(.caption2, design: .monospaced).weight(.heavy))
                    .foregroundStyle(ShoutOutHomeTheme.muted)
                Text(value)
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(caption)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ShoutOutHomeTheme.muted)
            }
        }
    }
}

private struct ActionPanel: View {
    let title: String
    let message: String
    let buttonTitle: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        HomePanel {
            VStack(alignment: .leading, spacing: 12) {
                Label(title, systemImage: systemImage)
                    .font(.headline)
                Text(message)
                    .foregroundStyle(ShoutOutHomeTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Button(buttonTitle, action: action)
                    .buttonStyle(HomeSecondaryButtonStyle())
            }
        }
    }
}

private struct PermissionChecklistRow: View {
    let title: String
    let detail: String
    let systemImage: String
    let isGranted: Bool
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HomePanel(background: isGranted ? ShoutOutHomeTheme.panelMint : ShoutOutHomeTheme.panel) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.title3.weight(.bold))
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(ShoutOutHomeTheme.muted)
                }

                Spacer()

                if isGranted {
                    Label("Granted", systemImage: "checkmark.circle.fill")
                        .font(.system(.caption, design: .monospaced).weight(.bold))
                } else {
                    Button(actionTitle, action: action)
                        .buttonStyle(HomePrimaryButtonStyle())
                }
            }
        }
    }
}

private struct TranscriptionHistoryRow: View {
    let entry: TranscriptionHistoryEntry
    @State private var showCleanupDetails: Bool
    @State private var didCopy = false
    @State private var copyFeedbackToken = UUID()

    init(entry: TranscriptionHistoryEntry) {
        self.entry = entry
        let cleanupOutput = entry.languagePassOutput ?? entry.text
        _showCleanupDetails = State(
            initialValue: entry.hasLanguagePassDetails
                && entry.languagePassInput != nil
                && entry.languagePassInput.map { $0 != cleanupOutput } == true
        )
    }

    var body: some View {
        HomePanel {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Label(entry.date.formatted(date: .abbreviated, time: .shortened), systemImage: "clock")
                        .font(.system(.caption, design: .monospaced).weight(.heavy))
                        .foregroundStyle(ShoutOutHomeTheme.muted)

                    Spacer(minLength: 8)

                    Text("\(entry.wordCount) \(entry.wordCount == 1 ? "word" : "words")")
                        .font(.system(.caption, design: .monospaced).weight(.heavy))
                        .foregroundStyle(ShoutOutHomeTheme.teal)
                }

                HistoryTranscriptTextWell(text: entry.text)

                if entry.hasLanguagePassDetails {
                    cleanupDetails
                }

                HStack(spacing: 10) {
                    Button {
                        copyText()
                    } label: {
                        Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(didCopy ? ShoutOutHomeTheme.ink : ShoutOutHomeTheme.muted)
                            .frame(width: 34, height: 30)
                            .pixelBox(
                                background: didCopy
                                    ? ShoutOutHomeTheme.panelMint
                                    : ShoutOutHomeTheme.panelBlue,
                                shadow: didCopy ? ShoutOutHomeTheme.teal : .clear,
                                shadowOffset: CGSize(width: didCopy ? 2 : 0, height: didCopy ? 2 : 0)
                            )
                    }
                    .buttonStyle(.plain)
                    .help(didCopy ? "Copied" : "Copy transcription")
                    .accessibilityLabel(didCopy ? "Copied" : "Copy transcription")

                    Text(durationText)
                        .font(.system(.caption, design: .monospaced).weight(.semibold))
                        .foregroundStyle(ShoutOutHomeTheme.muted)

                    Spacer()
                }
            }
        }
    }

    private var cleanupDetails: some View {
        DisclosureGroup(isExpanded: $showCleanupDetails) {
            VStack(alignment: .leading, spacing: 8) {
                if let input = entry.languagePassInput {
                    cleanupTextRow(title: "Before", text: input)
                }

                if let candidate = entry.languagePassCandidate,
                    candidate != cleanupOutput
                {
                    cleanupTextRow(title: "Model", text: candidate)
                }

                cleanupTextRow(title: "After", text: cleanupOutput)
            }
            .padding(.top, 8)
        } label: {
            HStack(spacing: 8) {
                Label("Language cleanup", systemImage: "sparkles")
                    .font(.system(.caption, design: .monospaced).weight(.heavy))
                Text(cleanupStatusText)
                    .font(.system(.caption, design: .monospaced).weight(.semibold))
                    .foregroundStyle(ShoutOutHomeTheme.muted)
                Spacer(minLength: 0)
            }
        }
        .tint(ShoutOutHomeTheme.teal)
    }

    private func cleanupTextRow(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(.caption2, design: .monospaced).weight(.heavy))
                .foregroundStyle(ShoutOutHomeTheme.muted)
            HistoryTranscriptTextWell(text: text, maxHeight: 96)
        }
    }

    private var cleanupOutput: String {
        entry.languagePassOutput ?? entry.text
    }

    private var cleanupStatusText: String {
        if let accepted = entry.languagePassAccepted {
            if accepted {
                return entry.languagePassInput.map { $0 == cleanupOutput } == true ? "accepted" : "cleaned"
            }
            return entry.languagePassFallbackReason ?? "fallback"
        }
        return entry.languagePassFallbackReason ?? "recorded"
    }

    private func copyText() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.text, forType: .string)

        let token = UUID()
        copyFeedbackToken = token
        didCopy = true

        Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            await MainActor.run {
                if copyFeedbackToken == token {
                    didCopy = false
                }
            }
        }
    }

    private var durationText: String {
        if entry.duration < 1 {
            return "<1 sec"
        }
        return "\(Int(round(entry.duration))) sec"
    }
}

private struct HistoryTranscriptTextWell: View {
    let text: String
    var maxHeight: CGFloat = 168

    var body: some View {
        ScrollView {
            Text(text)
                .font(.body.weight(.medium))
                .foregroundStyle(ShoutOutHomeTheme.ink)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(10)
        }
        .frame(maxWidth: .infinity, minHeight: 44, maxHeight: maxHeight, alignment: .topLeading)
        .background(ShoutOutHomeTheme.panelBlue.opacity(0.32))
        .overlay(ShoutOutHomeTheme.pixelBorder)
        .scrollIndicators(.visible)
    }
}

private struct SummaryPanel: View {
    let title: String
    let summary: UsageStatsSummary

    var body: some View {
        HomePanel {
            VStack(alignment: .leading, spacing: 10) {
                Text(title.uppercased())
                    .font(.system(.caption, design: .monospaced).weight(.heavy))
                    .foregroundStyle(ShoutOutHomeTheme.muted)
                Text("\(summary.wordCount)")
                    .font(.system(size: 40, weight: .heavy, design: .rounded))
                Text("\(summary.sessionCount) sessions · \(durationText)")
                    .foregroundStyle(ShoutOutHomeTheme.muted)
                Text("\(summary.averageWordsPerMinute) WPM average")
                    .font(.system(.caption, design: .monospaced).weight(.semibold))
                    .foregroundStyle(ShoutOutHomeTheme.muted)
            }
        }
    }

    private var durationText: String {
        let minutes = Int(round(summary.totalDuration / 60))
        return minutes < 1 ? "<1 min" : "\(minutes) min"
    }
}

private struct InsightMetricPanel: View {
    let title: String
    let value: String
    let caption: String

    var body: some View {
        HomePanel {
            VStack(alignment: .leading, spacing: 10) {
                Text(title.uppercased())
                    .font(.system(.caption, design: .monospaced).weight(.heavy))
                    .foregroundStyle(ShoutOutHomeTheme.muted)
                Text(value)
                    .font(.system(size: 38, weight: .heavy, design: .rounded))
                    .foregroundStyle(ShoutOutHomeTheme.ink)
                Text(caption)
                    .font(.system(.caption, design: .monospaced).weight(.semibold))
                    .foregroundStyle(ShoutOutHomeTheme.muted)
            }
        }
    }
}

private struct UsageDailyBarChart: View {
    let title: String
    let subtitle: String
    let days: [UsageDailySummary]
    let value: KeyPath<UsageDailySummary, Int>
    let color: Color

    var body: some View {
        HomePanel {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(.headline)
                    Spacer()
                    Text(subtitle)
                        .font(.system(.caption, design: .monospaced).weight(.semibold))
                        .foregroundStyle(ShoutOutHomeTheme.muted)
                }

                if days.isEmpty {
                    Text("Dictate a little and this will fill in.")
                        .font(.caption)
                        .foregroundStyle(ShoutOutHomeTheme.muted)
                        .frame(maxWidth: .infinity, minHeight: 150, alignment: .center)
                } else {
                    HStack(alignment: .bottom, spacing: 7) {
                        ForEach(days) { day in
                            DailyUsageBar(
                                day: day,
                                value: day[keyPath: value],
                                maxValue: maxValue,
                                color: color
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 150, alignment: .bottom)
                }
            }
        }
    }

    private var maxValue: Int {
        max(days.map { $0[keyPath: value] }.max() ?? 1, 1)
    }
}

private struct DailyUsageBar: View {
    let day: UsageDailySummary
    let value: Int
    let maxValue: Int
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            Text("\(value)")
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .foregroundStyle(ShoutOutHomeTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            GeometryReader { proxy in
                VStack {
                    Spacer(minLength: 0)
                    Rectangle()
                        .fill(color)
                        .frame(height: barHeight(in: proxy.size.height))
                        .overlay {
                            Rectangle()
                                .stroke(ShoutOutHomeTheme.ink, lineWidth: 1.5)
                        }
                }
            }
            .frame(height: 104)

            Text(dayLabel)
                .font(.system(size: 9, weight: .heavy, design: .monospaced))
                .foregroundStyle(ShoutOutHomeTheme.muted)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 142)
    }

    private func barHeight(in availableHeight: CGFloat) -> CGFloat {
        guard value > 0 else { return 4 }
        let ratio = CGFloat(value) / CGFloat(max(maxValue, 1))
        return max(8, availableHeight * ratio)
    }

    private var dayLabel: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "M/d"
        return formatter.string(from: day.date)
    }
}

private struct HomeStatusBadge: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: systemImage)
                .font(.system(.caption2, design: .monospaced).weight(.bold))
                .foregroundStyle(ShoutOutHomeTheme.muted)
            Text(value)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ShoutOutHomeTheme.panel)
        .overlay(ShoutOutHomeTheme.pixelBorder)
    }
}

private struct HomeSidebarButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, design: .rounded).weight(.heavy))
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .pixelBox(
                background: isSelected ? ShoutOutHomeTheme.coral : ShoutOutHomeTheme.panel,
                shadow: isSelected ? ShoutOutHomeTheme.ink : .clear,
                shadowOffset: CGSize(
                    width: isSelected ? 3 : 0,
                    height: isSelected ? 3 : 0
                )
            )
            .offset(
                x: configuration.isPressed ? 1 : 0,
                y: configuration.isPressed ? 1 : 0
            )
    }
}

private struct HomePrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.caption, design: .monospaced).weight(.heavy))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .foregroundStyle(ShoutOutHomeTheme.ink)
            .pixelBox(
                background: ShoutOutHomeTheme.coral,
                shadow: ShoutOutHomeTheme.ink,
                shadowOffset: CGSize(width: 3, height: 3)
            )
            .offset(x: configuration.isPressed ? 1 : 0, y: configuration.isPressed ? 1 : 0)
    }
}

private struct HomeSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.caption, design: .monospaced).weight(.heavy))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .foregroundStyle(ShoutOutHomeTheme.ink)
            .pixelBox(background: ShoutOutHomeTheme.panelBlue)
            .offset(x: configuration.isPressed ? 1 : 0, y: configuration.isPressed ? 1 : 0)
    }
}

private extension View {
    func pixelBox(
        background: Color,
        border: Color = ShoutOutHomeTheme.ink,
        shadow: Color = .clear,
        shadowOffset: CGSize = .zero
    ) -> some View {
        self
            .background {
                Rectangle()
                    .fill(shadow)
                    .offset(shadowOffset)
                Rectangle()
                    .fill(background)
            }
            .overlay {
                Rectangle()
                    .stroke(border, lineWidth: 2)
            }
    }

    func pixelBoxShadow(color: Color, offset: CGSize) -> some View {
        self
            .background {
                Rectangle()
                    .fill(color)
                    .offset(offset)
            }
    }
}

private extension NSImage {
    static func crabVariantSprite(named name: String, variant: CrabColorVariant) -> NSImage? {
        crabSprite(named: name, subdirectory: "CrabSpriteVariants/\(variant.rawValue)")
            ?? crabSprite(named: name, subdirectory: "CrabSprites")
    }

    static func crabSprite(named name: String, subdirectory: String) -> NSImage? {
        guard let url = Bundle.main.url(
            forResource: name,
            withExtension: "png",
            subdirectory: subdirectory
        ) else {
            return nil
        }

        return NSImage(contentsOf: url)
    }
}
