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
    @AppStorage(Defaults.crabColorVariant) private var crabColorVariant = CrabColorVariant.ocean.rawValue
    @AppStorage(Defaults.hotkeyTrigger) private var hotkeyTrigger = HotkeyTrigger.defaultTrigger.rawValue
    @AppStorage(Defaults.overlayStyle) private var overlayStyle = OverlayStyle.crab.rawValue
    @State private var isShowingDiagnostics = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var isConfirmingStatsClear = false
    @State private var isConfirmingHistoryClear = false
    @State private var visibleHistoryCount = 20
    @State private var historyQuery = ""
    @State private var historySearchResults: [TranscriptionHistoryEntry]?
    @FocusState private var historySearchFocused: Bool
    @State private var historySearchFocusRequest = 0

    var body: some View {
        HomeWindowShell {
            sidebar
        } content: {
            content
        }
        .frame(minWidth: 820, idealWidth: 1240, minHeight: 620, idealHeight: 760)
        .background(ShoutOutHomeTheme.background)
        .foregroundStyle(ShoutOutHomeTheme.ink)
        .environment(\.colorScheme, .light)
        .onChange(of: model.selectedSection) { _, section in
            isShowingDiagnostics = false
            if section == .history { visibleHistoryCount = 20 }
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
                visibleHistoryCount = 20
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
                    .buttonStyle(HomeSelectionButtonStyle(isSelected: model.selectedSection == section))
                }
            }

            Spacer()

            HomeStatusBadge(
                title: "Shortcut",
                value: selectedHotkeyTrigger.displayName,
                systemImage: "keyboard"
            )

            HomeStatusBadge(
                title: "Dictation",
                value: "On-device English",
                systemImage: "waveform.path.ecg"
            )
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(ShoutOutHomeTheme.sidebar)
    }

    @ViewBuilder
    private var content: some View {
        ScrollViewReader { scroll in
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
            .onChange(of: historyQuery) { _, _ in
                scroll.scrollTo("history-search", anchor: .top)
            }
            .onChange(of: historySearchFocusRequest) { _, _ in
                scroll.scrollTo("history-search", anchor: .top)
            }
        }
        .id(model.selectedSection)
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
                    title: "Writing",
                    value: languagePass.isEnabled ? languagePass.selectedStyle.title : "As spoken",
                    caption: languagePass.isEnabled ? "text cleanup enabled" : "text cleanup off",
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
                    title: "Make it yours",
                    message: "Your shortcut, writing style, and a crab in your favorite color.",
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
                if !permissions.missingPermissionNames.isEmpty {
                    Button("Open Missing") {
                        permissions.openFirstMissingPermissionPane()
                    }
                    .buttonStyle(HomePrimaryButtonStyle())
                }

                Button("Refresh") {
                    permissions.refresh()
                }
                .buttonStyle(HomeSecondaryButtonStyle())
            }
        }
    }

    private var historyPage: some View {
        let allEntries = transcriptionHistory.recentEntries
        let query = historyQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let entries = query.isEmpty ? allEntries : (historySearchResults ?? [])
        let request = HistorySearchRequest(query: query, entries: allEntries)
        return VStack(alignment: .leading, spacing: 16) {
            PageHeader(
                title: "History",
                subtitle: "Recent local transcriptions saved on this Mac."
            )

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(ShoutOutHomeTheme.muted)
                TextField("Search transcriptions…", text: $historyQuery)
                    .textFieldStyle(.plain)
                    .focused($historySearchFocused)
                    .accessibilityLabel("Search transcription history")
                    .onExitCommand { historyQuery = "" }
                if !historyQuery.isEmpty {
                    Button {
                        historyQuery = ""
                        historySearchFocused = true
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(14)
            .background(ShoutOutHomeTheme.panel)
            .overlay(Rectangle().stroke(ShoutOutHomeTheme.ink, lineWidth: 2))
            .id("history-search")

            if !query.isEmpty && historySearchResults == nil {
                ProgressView("Searching history…")
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if entries.isEmpty {
                HomePanel {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(query.isEmpty ? "No transcriptions yet" : "No matching transcriptions",
                              systemImage: query.isEmpty ? "text.badge.plus" : "magnifyingglass")
                            .font(.headline)
                        Text(query.isEmpty
                             ? "Your pasted dictations will show up here after ShoutOut captures text."
                             : "Try fewer words or a different spelling.")
                            .foregroundStyle(ShoutOutHomeTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(entries.prefix(visibleHistoryCount)) { entry in
                        TranscriptionHistoryRow(entry: entry)
                    }
                }

                HStack {
                    if visibleHistoryCount < entries.count {
                        Button(query.isEmpty ? "Show older transcriptions" : "Show more matches") {
                            visibleHistoryCount += 20
                        }
                        .buttonStyle(HomeSecondaryButtonStyle())
                    }
                    Text("\(min(visibleHistoryCount, entries.count)) of \(entries.count)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(ShoutOutHomeTheme.muted)
                    Spacer()
                    if query.isEmpty {
                        Button("Clear History", role: .destructive) {
                            isConfirmingHistoryClear = true
                        }
                        .buttonStyle(HomeSecondaryButtonStyle())
                    }
                }
            }
        }
        .task(id: request) {
            visibleHistoryCount = 20
            historySearchResults = nil
            guard !query.isEmpty else { return }
            do {
                try await Task.sleep(for: .milliseconds(150))
                let search = Task.detached(priority: .userInitiated) {
                    try TranscriptionHistorySearch.search(request.entries, query: request.query)
                }
                let matches = try await withTaskCancellationHandler {
                    try await search.value
                } onCancel: {
                    search.cancel()
                }
                try Task.checkCancellation()
                historySearchResults = matches
            } catch is CancellationError {
                // A newer query or navigation replaced this search.
            } catch {
                historySearchResults = []
            }
        }
        .background {
            Button("Find in history") {
                historySearchFocusRequest += 1
                historySearchFocused = true
            }
                .keyboardShortcut("f", modifiers: .command)
                .hidden()
        }
    }

    private var settingsPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(title: "Settings", subtitle: "Good defaults. A few things to make yours.")
            dictationStatus
            writingSettings
            personalSettings
            settingsFooter
        }
        .frame(maxWidth: 760, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var dictationStatus: some View {
        HomePanel(background: Color(red: 0.83, green: 0.94, blue: 0.92)) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "waveform")
                        .font(.title2.weight(.semibold))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("English dictation")
                            .font(.headline)
                        Text("Fast, private, and on your Mac.")
                            .font(.subheadline)
                            .foregroundStyle(ShoutOutHomeTheme.muted)
                    }
                    Spacer()
                    Label(modelStatusText, systemImage: "circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(modelStatusColor)
                }
                if let progress = transcription.modelState.startupProgress,
                    !transcription.modelState.isReady {
                    ModelProgressBar(progress: progress, height: 6)
                    Text("Preparing your local models. First setup downloads about 5 GB.")
                        .font(.caption)
                        .foregroundStyle(ShoutOutHomeTheme.muted)
                }
                if case .error(let message) = transcription.modelState {
                    Text(message).font(.caption).textSelection(.enabled)
                    Button("Try again") { Task { await transcription.loadModel() } }
                        .buttonStyle(HomeSecondaryButtonStyle())
                } else if transcription.modelState == .unloaded {
                    Button("Prepare dictation") { Task { await transcription.loadModel() } }
                        .buttonStyle(HomeSecondaryButtonStyle())
                }
            }
        }
    }

    private var writingSettings: some View {
        HomeSettingSection(title: "Writing", systemImage: "text.cursor") {
            HomeToggleRow(
                title: "Text cleanup",
                detail: "Clean up stutters, repeated starts, and obvious self-corrections.",
                systemImage: "sparkles",
                isOn: $languagePass.isEnabled
            )
            if languagePass.isEnabled {
                Divider()
                HStack(spacing: 8) {
                    ForEach(LanguagePassStyle.allCases) { style in
                        let isSelected = languagePass.selectedStyle == style
                        Button {
                            languagePass.selectedStyle = style
                        } label: {
                            Text(style.title)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(HomeSelectionButtonStyle(isSelected: isSelected))
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Writing style")
                Text(languagePass.selectedStyle.detail)
                    .font(.subheadline)
                    .foregroundStyle(ShoutOutHomeTheme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let progress = languagePass.modelState.startupProgress,
                    !languagePass.modelState.isReady {
                    ModelProgressBar(progress: progress, height: 6)
                    Text(languagePassProgressCaption)
                        .font(.caption)
                        .foregroundStyle(ShoutOutHomeTheme.muted)
                }
                if case .error = languagePass.modelState {
                    HStack {
                        Text("Cleanup couldn't start. Dictation still works.")
                            .font(.caption)
                        Spacer()
                        Button("Try again") { Task { await languagePass.prepareIfNeeded() } }
                            .buttonStyle(HomeSecondaryButtonStyle())
                    }
                }
            }
        }
    }

    private var personalSettings: some View {
        HomeSettingSection(title: "Make it yours", systemImage: "hand.wave") {
            HomeControlRow(title: "Shortcut", detail: "Hold to speak. Double-press for hands-free.", systemImage: "keyboard") {
                HomeStringMenu(
                    selection: $hotkeyTrigger,
                    choices: HotkeyTrigger.allCases.map {
                        HomeStringChoice(value: $0.rawValue, title: $0.displayName)
                    },
                    width: 170
                ) { (NSApp.delegate as? AppDelegate)?.restartHotkey() }
            }
            Divider()
            HomeControlRow(title: "Indicator", systemImage: "macwindow") {
                HomeStringMenu(
                    selection: $overlayStyle,
                    choices: [
                        HomeStringChoice(value: OverlayStyle.crab.rawValue, title: "Crab"),
                        HomeStringChoice(value: OverlayStyle.capsule.rawValue, title: "Classic"),
                    ],
                    width: 176
                ) { (NSApp.delegate as? AppDelegate)?.refreshOverlay() }
            }
            Divider()
            if overlayStyle == OverlayStyle.crab.rawValue {
                HomeControlRow(title: "Crab color", systemImage: "paintpalette") {
                    HomeCrabColorMenu(selection: $crabColorVariant, width: 176) {
                        (NSApp.delegate as? AppDelegate)?.refreshOverlay()
                    }
                }
                Divider()
            }
            HomeToggleRow(title: "Launch at login", systemImage: "arrow.right.circle", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, newValue in
                    do {
                        if newValue {
                            try SMAppService.mainApp.register()
                        } else {
                            try SMAppService.mainApp.unregister()
                        }
                    } catch {
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                        NSAlert(error: error).runModal()
                    }
                }
        }
    }

    private var settingsFooter: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                settingsVersion
                Spacer()
                settingsSupport
            }
            VStack(alignment: .leading, spacing: 12) {
                settingsVersion
                settingsSupport
            }
        }
        .font(.system(.caption, design: .monospaced).weight(.semibold))
        .foregroundStyle(ShoutOutHomeTheme.muted)
        .padding(.vertical, 4)
    }

    private var settingsVersion: some View {
        Button("ShoutOut \(AppVersionInfo.version)") { copyVersionInfo() }
            .buttonStyle(.plain)
            .help("Copy version and build information")
    }

    private var settingsSupport: some View {
        HStack(spacing: 12) {
            Button("Check for updates") {
                (NSApp.delegate as? AppDelegate)?.checkForUpdates()
            }
            .buttonStyle(HomeSecondaryButtonStyle())
            Button {
                isShowingDiagnostics.toggle()
            } label: {
                HStack(spacing: 6) {
                    Text("Help & diagnostics")
                    Image(systemName: "chevron.down")
                }
            }
            .buttonStyle(HomeSecondaryButtonStyle())
            .squarePopover(isPresented: $isShowingDiagnostics) {
                HomeMenuPopover(width: 240) {
                    HomeMenuOption(title: "Export diagnostics…", isSelected: false) {
                        isShowingDiagnostics = false
                        exportDiagnostics()
                    }
                    HomeMenuOption(title: "Show runtime log", isSelected: false) {
                        isShowingDiagnostics = false
                        NSWorkspace.shared.activateFileViewerSelecting([RuntimeLog.logURL])
                    }
                    HomeMenuOption(title: "Show model files", isSelected: false) {
                        isShowingDiagnostics = false
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: TranscriptionService.modelsDirectory.path)
                    }
                }
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
        case .ready: return Color(red: 0.08, green: 0.40, blue: 0.30)
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
    static let background = Color(red: 0.88, green: 0.93, blue: 0.97)
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

private enum HomeWindowLayout {
    static let sidebarWidth: CGFloat = 240
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
                .font(.system(size: 26, weight: .heavy, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
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
                shadowOffset: CGSize(width: 3, height: 3)
            )
    }
}

private struct HomeSettingSection<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        HomePanel {
            VStack(alignment: .leading, spacing: 14) {
                Label(title, systemImage: systemImage)
                    .font(.system(.title3, design: .rounded).weight(.heavy))
                VStack(spacing: 10) {
                    content
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(
                maxWidth: .infinity,
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
        .padding(.vertical, 4)
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
        .squarePopover(isPresented: $isOpen) {
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
        .squarePopover(isPresented: $isOpen) {
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
        .overlay(Rectangle().strokeBorder(ShoutOutHomeTheme.ink, lineWidth: 2))
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
        .toggleStyle(HomePixelToggleStyle())
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }
}

private struct HomePixelToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.12)) {
                configuration.isOn.toggle()
            }
        } label: {
            HStack(alignment: .center, spacing: 12) {
                configuration.label
                Spacer(minLength: 12)
                HomePixelSwitch(isOn: configuration.isOn)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
    }
}

private struct HomePixelSwitch: View {
    let isOn: Bool

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Rectangle()
                .fill(isOn ? ShoutOutHomeTheme.panelMint : ShoutOutHomeTheme.panel)
            Rectangle()
                .stroke(ShoutOutHomeTheme.ink, lineWidth: 2)
            Rectangle()
                .fill(isOn ? ShoutOutHomeTheme.teal : ShoutOutHomeTheme.muted.opacity(0.42))
                .frame(width: 16, height: 16)
                .padding(4)
        }
        .frame(width: 46, height: 24)
        .animation(.easeInOut(duration: 0.12), value: isOn)
        .accessibilityHidden(true)
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
    @State private var showCleanupDetails = false
    @State private var didCopy = false
    @State private var copyFeedbackToken = UUID()

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

                if entry.hasLanguagePassDetails {
                    cleanupDetails
                }
            }
        }
    }

    private var cleanupDetails: some View {
        DisclosureGroup(isExpanded: $showCleanupDetails) {
            if showCleanupDetails {
                VStack(alignment: .leading, spacing: 8) {
                    cleanupTraceRows

                    if cleanupDidChange, let input = entry.languagePassInput {
                        cleanupTextRow(title: "Before", text: input)

                        if entry.languagePassAccepted == true,
                            let candidate = entry.languagePassCandidate,
                            candidate != cleanupOutput
                        {
                            cleanupTextRow(title: "Model", text: candidate)
                        }

                        cleanupTextRow(title: "After", text: cleanupOutput)
                    }
                }
                .padding(.top, 8)
            }
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

    private var cleanupTraceRows: some View {
        VStack(alignment: .leading, spacing: 5) {
            cleanupTraceRow(title: "Reason", value: cleanupReasonText)
            if let cleanupToneText {
                cleanupTraceRow(title: "Tone", value: cleanupToneText)
            }
        }
    }

    private func cleanupTraceRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.system(.caption2, design: .monospaced).weight(.heavy))
                .foregroundStyle(ShoutOutHomeTheme.muted)
                .frame(width: 48, alignment: .leading)
            Text(value)
                .font(.system(.caption, design: .monospaced).weight(.semibold))
                .foregroundStyle(ShoutOutHomeTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
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

    private var cleanupDidChange: Bool {
        LanguagePassDisplayCopy.didChange(
            input: entry.languagePassInput,
            output: cleanupOutput
        )
    }

    private var cleanupStatusText: String {
        LanguagePassDisplayCopy.status(
            accepted: entry.languagePassAccepted,
            changed: cleanupDidChange,
            fallbackReason: entry.languagePassFallbackReason
        )
    }

    private var cleanupReasonText: String {
        LanguagePassDisplayCopy.reason(
            accepted: entry.languagePassAccepted,
            changed: cleanupDidChange,
            fallbackReason: entry.languagePassFallbackReason,
            styleRawValue: entry.languagePassStyle
        )
    }

    private var cleanupToneText: String? {
        LanguagePassDisplayCopy.toneTitle(entry.languagePassStyle)
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

private struct HomeSelectionButtonStyle: ButtonStyle {
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

private struct HistorySearchRequest: Equatable {
    let query: String
    let entries: [TranscriptionHistoryEntry]
}
