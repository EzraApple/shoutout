import AppKit
import Combine
import ShoutOutCore
import SwiftUI

enum Defaults {
    static let showInDock = "showInDock"
    static let dimSystemAudio = "dimSystemAudio"
    static let overlayStyle = "overlayStyle"
    static let requestPermissionsOnLaunch = "requestPermissionsOnLaunch"
    static let cleanUpSelfCorrections = "cleanUpSelfCorrections"
}

// MARK: - App State

enum AppState: Equatable {
    case initializing(progress: Double?)
    case idle
    case recording
    case processing
}

private enum DictationInputMode: String {
    case hold
    case handsFree
    case unknown
}

private struct DictationLatencyMetrics {
    let id = UUID().uuidString.prefix(8)
    var inputMode: DictationInputMode = .unknown
    var firstFnPressAt = Date()
    var recordStartRequestedAt: Date?
    var recorderStartedAt: Date?
    var recordingCommittedAt: Date?
    var stopRequestedAt: Date?
    var samplesReadyAt: Date?
    var transcriptionQueuedAt: Date?
    var transcriptionDequeuedAt: Date?
    var transcriptionCompletedAt: Date?
    var pastePostedAt: Date?
    var sampleCount = 0
    var recordingDuration: TimeInterval = 0
    var finalTextLength = 0
    var wordCount = 0
    var model = ""

    mutating func markRecordingStarted(sampleCount: Int = 0) {
        recorderStartedAt = Date()
        self.sampleCount = sampleCount
    }

    func log(status: String, transcriptionTiming: TranscriptionTimingSnapshot? = nil) {
        RuntimeLog.write(
            [
                "dictation metrics",
                "id=\(id)",
                "status=\(status)",
                "mode=\(inputMode.rawValue)",
                metric("pressToRecordStartMs", firstFnPressAt, recorderStartedAt),
                metric("pressToCommitMs", firstFnPressAt, recordingCommittedAt),
                metric("recordStartRequestToReadyMs", recordStartRequestedAt, recorderStartedAt),
                metric("stopToSamplesMs", stopRequestedAt, samplesReadyAt),
                metric("stopToPasteMs", stopRequestedAt, pastePostedAt),
                metric("queueWaitMs", transcriptionQueuedAt, transcriptionDequeuedAt),
                metric("transcriptionWallMs", transcriptionDequeuedAt, transcriptionCompletedAt),
                "recordingMs=\(Int(recordingDuration * 1000))",
                "samples=\(sampleCount)",
                "words=\(wordCount)",
                "chars=\(finalTextLength)",
                "model=\(model)",
                transcriptionTiming?.logFields ?? "",
            ].filter { !$0.isEmpty }.joined(separator: " ")
        )
    }

    private func metric(_ name: String, _ start: Date?, _ end: Date?) -> String {
        guard let start, let end else { return "\(name)=na" }
        return "\(name)=\(Int(end.timeIntervalSince(start) * 1000))"
    }

    func performanceSnapshot(transcriptionTiming: TranscriptionTimingSnapshot)
        -> UsagePerformanceMetrics
    {
        UsagePerformanceMetrics(
            inputMode: inputMode.rawValue,
            pressToRecordStartMs: elapsedMilliseconds(from: firstFnPressAt, to: recorderStartedAt),
            pressToCommitMs: elapsedMilliseconds(from: firstFnPressAt, to: recordingCommittedAt),
            recordStartRequestToReadyMs: elapsedMilliseconds(
                from: recordStartRequestedAt,
                to: recorderStartedAt
            ),
            stopToSamplesMs: elapsedMilliseconds(from: stopRequestedAt, to: samplesReadyAt),
            stopToPasteMs: elapsedMilliseconds(from: stopRequestedAt, to: pastePostedAt),
            queueWaitMs: elapsedMilliseconds(from: transcriptionQueuedAt, to: transcriptionDequeuedAt),
            transcriptionWallMs: elapsedMilliseconds(
                from: transcriptionDequeuedAt,
                to: transcriptionCompletedAt
            ),
            recordingMs: Int(recordingDuration * 1000),
            modelWaitMs: transcriptionTiming.modelWaitMs,
            whisperWallMs: transcriptionTiming.whisperWallMs,
            postProcessMs: transcriptionTiming.postProcessMs,
            firstTokenMs: transcriptionTiming.firstTokenMs,
            whisperPipelineMs: transcriptionTiming.whisperPipelineMs,
            realTimeFactor: transcriptionTiming.realTimeFactor,
            speedFactor: transcriptionTiming.speedFactor,
            tokensPerSecond: transcriptionTiming.tokensPerSecond,
            fallbackCount: transcriptionTiming.fallbackCount
        )
    }

    private func elapsedMilliseconds(from start: Date?, to end: Date?) -> Int? {
        guard let start, let end else { return nil }
        return Int(end.timeIntervalSince(start) * 1000)
    }
}

// MARK: - App Delegate (Menu Bar App)

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    let audioRecorder = AudioRecorder()
    let transcriptionService = TranscriptionService()
    let hotkeyManager = HotkeyManager()
    let permissions = PermissionManager.shared
    let usageStats = UsageStatsStore.defaultStore()
    let audioDucker = SystemAudioDucker()

    var settingsWindow: NSWindow?
    var onboardingWindow: NSWindow?
    private var appState: AppState = .idle
    private var recordingStartedAt: Date?
    private var recordingIsCommitted = false
    private var pendingTranscriptionCount = 0
    private var transcriptionQueueTail: Task<Void, Never>?
    private var activeDictationMetrics: DictationLatencyMetrics?

    /// Prevent App Nap from making the hotkey unresponsive
    private var activityToken: NSObjectProtocol?

    // MARK: - Floating Indicator

    private var indicatorPanel: NSPanel?
    private var indicatorHostingView: NSHostingView<AppOverlayView>?
    private var currentIndicatorState: IndicatorState = .idle
    private var audioLevelCancellable: AnyCancellable?
    private var indicatorDismissTask: Task<Void, Never>?
    private var modelStateCancellable: AnyCancellable?
    private var shortcutUnavailableMessage: String?
    private var lastLoggedRecordingLevelAt: Date?
    private var permissionChangeObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        RuntimeLog.write("app launch bundle=\(Bundle.main.bundleIdentifier ?? "unknown")")
        UserDefaults.standard.register(defaults: [
            Defaults.showInDock: true,
            Defaults.dimSystemAudio: true,
            Defaults.overlayStyle: OverlayStyle.crab.rawValue,
            "removeFillerWords": true,
            Defaults.cleanUpSelfCorrections: true,
        ])

        let overlayPreviewState = requestedOverlayPreviewState()

        setupMainMenu()
        setupMenuBar()
        observeModelState()
        if overlayPreviewState == nil {
            setupHotkey()
        }

        if UserDefaults.standard.bool(forKey: Defaults.showInDock) {
            NSApp.setActivationPolicy(.regular)
        }

        // Re-check permissions when app becomes active (user returns from System Settings)
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.permissions.refresh()
                self?.setupHotkey()
                self?.refreshOverlay()
            }
        }
        permissionChangeObserver = NotificationCenter.default.addObserver(
            forName: .shoutOutPermissionsChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                RuntimeLog.write("permissions changed; retrying hotkey setup")
                self?.setupHotkey()
                self?.refreshOverlay()
                self?.continuePermissionSetupIfRequested()
            }
        }

        // Prevent App Nap
        activityToken = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep,
            reason: "Global hotkey monitoring"
        )

        // Check onboarding
        if overlayPreviewState == nil
            && !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        {
            showOnboarding()
        }

        if overlayPreviewState == nil {
            // Load model in background (recording is allowed even before it's ready)
            Task {
                await transcriptionService.loadModel()
            }
        }

        if overlayPreviewState == nil,
            UserDefaults.standard.bool(forKey: Defaults.requestPermissionsOnLaunch)
        {
            Task { @MainActor in
                RuntimeLog.write("permissions diagnostic request-on-launch start")
                permissions.openFirstMissingPermissionPane()
            }
        }

        Task { @MainActor in
            showIndicator(state: overlayPreviewState ?? currentIdleIndicatorState())
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        RuntimeLog.write("app terminate")
        if let permissionChangeObserver {
            NotificationCenter.default.removeObserver(permissionChangeObserver)
        }
        modelStateCancellable?.cancel()
        hotkeyManager.stop()
        transcriptionQueueTail?.cancel()
        if audioRecorder.isRecording {
            _ = audioRecorder.stopRecording()
        }
        recordingIsCommitted = false
        audioDucker.endDucking()
        if let token = activityToken {
            ProcessInfo.processInfo.endActivity(token)
        }
        dismissIndicator()
    }

    // MARK: - Hotkey Setup

    private func setupHotkey() {
        guard appState == .idle else { return }

        permissions.refresh()
        guard permissions.hasAccessibility, permissions.hasInputMonitoring else {
            RuntimeLog.write(
                "hotkey setup blocked accessibility=\(permissions.hasAccessibility) inputMonitoring=\(permissions.hasInputMonitoring)"
            )
            shortcutUnavailableMessage = permissions.hotkeyStatusText
            showIndicator(state: currentIdleIndicatorState())
            return
        }

        hotkeyManager.onRecordArmed = { [weak self] in
            self?.startPendingRecording()
        }
        hotkeyManager.onRecordCancelled = { [weak self] in
            self?.cancelPendingRecording()
        }
        hotkeyManager.onRecordStart = { [weak self] in
            self?.commitRecording()
        }
        hotkeyManager.onRecordStop = { [weak self] in
            self?.stopRecordingAndTranscribe()
        }
        hotkeyManager.onShortcutUnavailable = { [weak self] message in
            RuntimeLog.write("hotkey unavailable message=\(message)")
            self?.shortcutUnavailableMessage = message
            self?.showTransientAttention(message)
        }

        if hotkeyManager.start() {
            RuntimeLog.write("hotkey setup complete")
            shortcutUnavailableMessage = nil
            if currentIndicatorState.hasAttention {
                showIndicator(state: currentIdleIndicatorState())
            }
        } else {
            RuntimeLog.write("hotkey setup failed")
        }
    }

    private func continuePermissionSetupIfRequested() {
        guard UserDefaults.standard.bool(forKey: Defaults.requestPermissionsOnLaunch) else {
            return
        }
        guard !permissions.missingPermissionNames.isEmpty else {
            UserDefaults.standard.set(false, forKey: Defaults.requestPermissionsOnLaunch)
            RuntimeLog.write("permissions diagnostic request-on-launch complete")
            return
        }
        permissions.openFirstMissingPermissionPane()
    }

    // MARK: - Recording Flow

    private func startPendingRecording() {
        guard appState == .idle else { return }
        RuntimeLog.write("record arm")
        activeDictationMetrics = DictationLatencyMetrics()
        startRecording(commitImmediately: false)
    }

    private func cancelPendingRecording() {
        if audioRecorder.isRecording, !recordingIsCommitted {
            discardActiveRecording(reason: "quickRelease")
            return
        }

        guard appState == .idle else { return }
        RuntimeLog.write("record arm cancelled")
        finishIndicator()
    }

    private func commitRecording() {
        guard appState == .recording else {
            startRecording(commitImmediately: true)
            return
        }

        guard !recordingIsCommitted else { return }
        recordingIsCommitted = true
        activeDictationMetrics?.inputMode = .hold
        activeDictationMetrics?.recordingCommittedAt = Date()
        RuntimeLog.write("record committed")
        audioDucker.beginDuckingIfEnabled()
    }

    private func startRecording(commitImmediately: Bool) {
        guard appState == .idle else { return }
        let startRequestedAt = Date()
        RuntimeLog.write("record start requested")
        if activeDictationMetrics == nil {
            activeDictationMetrics = DictationLatencyMetrics()
        }
        activeDictationMetrics?.inputMode = commitImmediately ? .handsFree : .unknown
        activeDictationMetrics?.recordStartRequestedAt = startRequestedAt

        permissions.refresh()
        guard permissions.hasMicrophone else {
            RuntimeLog.write("record start blocked microphone=false")
            hotkeyManager.cancelRecording()
            Task { @MainActor in
                let granted = await permissions.requestMicrophone()
                if granted {
                    finishIndicator()
                } else {
                    showTransientAttention("Mic off")
                }
            }
            return
        }

        do {
            recordingStartedAt = Date()
            appState = .recording
            recordingIsCommitted = commitImmediately
            refreshMenuBarIcon()
            showIndicator(state: .recording(level: 0))
            try audioRecorder.startRecording()
            let elapsedMs = Int(Date().timeIntervalSince(startRequestedAt) * 1000)
            activeDictationMetrics?.markRecordingStarted()
            RuntimeLog.write("record started elapsedMs=\(elapsedMs)")
            if commitImmediately {
                activeDictationMetrics?.recordingCommittedAt = Date()
                RuntimeLog.write("record committed")
                audioDucker.beginDuckingIfEnabled()
            }

            // Subscribe to audio level updates
            audioLevelCancellable = audioRecorder.$audioLevel
                .receive(on: RunLoop.main)
                .sink { [weak self] level in
                    self?.logRecordingLevel(level)
                    self?.updateIndicator(state: .recording(level: level))
                }
        } catch {
            recordingStartedAt = nil
            recordingIsCommitted = false
            audioDucker.endDucking()
            appState = .idle
            refreshMenuBarIcon()
            hotkeyManager.cancelRecording()
            showTransientAttention("Mic failed")
            activeDictationMetrics?.log(status: "recordStartFailed")
            activeDictationMetrics = nil
            RuntimeLog.write("record start failed error=\(error)")
        }
    }

    private func stopRecordingAndTranscribe() {
        guard audioRecorder.isRecording else { return }
        activeDictationMetrics?.stopRequestedAt = Date()
        RuntimeLog.write("record stop requested")

        audioLevelCancellable?.cancel()
        audioLevelCancellable = nil

        let samples = audioRecorder.stopRecording()
        activeDictationMetrics?.samplesReadyAt = Date()
        activeDictationMetrics?.sampleCount = samples.count
        let recordingDuration = max(
            Date().timeIntervalSince(recordingStartedAt ?? Date()),
            Double(samples.count) / AudioRecorder.sampleRate
        )
        activeDictationMetrics?.recordingDuration = recordingDuration
        activeDictationMetrics?.model = transcriptionService.selectedModel
        recordingStartedAt = nil
        recordingIsCommitted = false
        appState = .idle
        audioDucker.endDucking()
        RuntimeLog.write(
            "record stopped samples=\(samples.count) duration=\(String(format: "%.2f", recordingDuration))"
        )

        guard samples.count >= AudioRecorder.minimumSamples else {
            refreshMenuBarIcon()
            showTransientAttention("No audio", durationNanoseconds: 700_000_000)
            activeDictationMetrics?.log(status: "noAudio")
            activeDictationMetrics = nil
            RuntimeLog.write("record stopped noAudio samples=\(samples.count)")
            return
        }

        let signal = AudioSignalAnalysis.analyze(samples: samples)
        RuntimeLog.write(
            "record signal rms=\(String(format: "%.6f", signal.rms)) peak=\(String(format: "%.6f", signal.peak)) activeRatio=\(String(format: "%.4f", signal.activeRatio))"
        )

        guard signal.hasSpeechLikeAudio else {
            refreshMenuBarIcon()
            showTransientAttention("No speech", durationNanoseconds: 700_000_000)
            activeDictationMetrics?.log(status: "silent")
            activeDictationMetrics = nil
            RuntimeLog.write(
                "record stopped silent rms=\(String(format: "%.6f", signal.rms)) peak=\(String(format: "%.6f", signal.peak)) activeRatio=\(String(format: "%.4f", signal.activeRatio))"
            )
            return
        }

        var metrics = activeDictationMetrics ?? DictationLatencyMetrics()
        metrics.sampleCount = samples.count
        metrics.recordingDuration = recordingDuration
        metrics.model = transcriptionService.selectedModel
        metrics.transcriptionQueuedAt = Date()
        activeDictationMetrics = nil
        enqueueTranscription(
            samples: samples,
            recordingDuration: recordingDuration,
            metrics: metrics
        )
    }

    private func discardActiveRecording(reason: String) {
        RuntimeLog.write("record discard requested reason=\(reason)")
        audioLevelCancellable?.cancel()
        audioLevelCancellable = nil

        let samples = audioRecorder.stopRecording()
        let recordingDuration = max(
            Date().timeIntervalSince(recordingStartedAt ?? Date()),
            Double(samples.count) / AudioRecorder.sampleRate
        )
        recordingStartedAt = nil
        recordingIsCommitted = false
        appState = .idle
        audioDucker.endDucking()
        refreshMenuBarIcon()
        finishIndicator()
        activeDictationMetrics?.sampleCount = samples.count
        activeDictationMetrics?.recordingDuration = recordingDuration
        activeDictationMetrics?.log(status: reason)
        activeDictationMetrics = nil
        RuntimeLog.write(
            "record discarded reason=\(reason) samples=\(samples.count) duration=\(String(format: "%.2f", recordingDuration))"
        )
    }

    private func enqueueTranscription(
        samples: [Float],
        recordingDuration: TimeInterval,
        metrics: DictationLatencyMetrics
    ) {
        pendingTranscriptionCount += 1
        refreshMenuBarIcon()
        if appState == .idle {
            updateIndicator(state: .processing)
        }
        RuntimeLog.write("transcription queued pending=\(pendingTranscriptionCount)")

        let previousTail = transcriptionQueueTail
        let task = Task { [weak self] in
            await previousTail?.value
            await self?.processQueuedTranscription(
                samples: samples,
                recordingDuration: recordingDuration,
                metrics: metrics
            )
        }
        transcriptionQueueTail = task
    }

    private func processQueuedTranscription(
        samples: [Float],
        recordingDuration: TimeInterval,
        metrics initialMetrics: DictationLatencyMetrics
    ) async {
        if Task.isCancelled { return }
        var metrics = initialMetrics
        metrics.transcriptionDequeuedAt = Date()
        RuntimeLog.write("transcription dequeued pending=\(pendingTranscriptionCount)")

        defer {
            pendingTranscriptionCount = max(pendingTranscriptionCount - 1, 0)
            refreshMenuBarIcon()
            if pendingTranscriptionCount == 0,
                appState == .idle,
                currentIndicatorState == .processing
            {
                finishIndicator()
            }
        }

        do {
            // transcribe() waits for the model if it's still loading.
            let transcription = try await transcriptionService.transcribeWithTiming(
                audioSamples: samples
            )
            let result = transcription.result
            metrics.transcriptionCompletedAt = Date()
            metrics.finalTextLength = result.finalText.count
            metrics.wordCount = estimatedWordCount(in: result.finalText)
            RuntimeLog.write(
                "transcription complete rawLength=\(result.rawText.count) finalLength=\(result.finalText.count)"
            )
            if !result.finalText.isEmpty {
                let performance = metrics.performanceSnapshot(
                    transcriptionTiming: transcription.timing
                )
                try? usageStats.record(
                    finalText: result.finalText,
                    duration: recordingDuration,
                    model: transcriptionService.selectedModel,
                    performance: performance
                )
                TextInserter.insertText(result.finalText)
                metrics.pastePostedAt = Date()
                metrics.log(status: "inserted", transcriptionTiming: transcription.timing)
                showTranscriptionResultIndicator(.done(text: result.finalText))
            } else {
                showTranscriptionResultIndicator(
                    .attention(message: "No speech"),
                    durationNanoseconds: 900_000_000
                )
                metrics.log(status: "empty", transcriptionTiming: transcription.timing)
                RuntimeLog.write("transcription empty")
            }
        } catch {
            metrics.transcriptionCompletedAt = Date()
            metrics.log(status: "failed")
            RuntimeLog.write("transcription failed error=\(error)")
            showTranscriptionResultIndicator(
                .attention(message: "Transcription failed"),
                durationNanoseconds: 1_200_000_000
            )
        }
    }

    private func estimatedWordCount(in text: String) -> Int {
        text.split { $0.isWhitespace || $0.isNewline }.count
    }

    private func logRecordingLevel(_ level: Float) {
        let now = Date()
        if let lastLoggedRecordingLevelAt,
            now.timeIntervalSince(lastLoggedRecordingLevelAt) < 0.5
        {
            return
        }
        lastLoggedRecordingLevelAt = now
        RuntimeLog.write("record level=\(String(format: "%.3f", level))")
    }

    // MARK: - Floating Indicator

    private func observeModelState() {
        modelStateCancellable = transcriptionService.$modelState
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                self?.handleModelStateChange(state)
            }
    }

    private func handleModelStateChange(_ state: ModelState) {
        refreshMenuBarIcon()
        if state.isReady {
            refreshOverlay()
        } else {
            hideIndicatorPanel()
        }
    }

    private func showIndicator(state: IndicatorState) {
        indicatorDismissTask?.cancel()
        indicatorDismissTask = nil
        currentIndicatorState = state

        guard modelIsReadyForOverlay else {
            hideIndicatorPanel()
            return
        }

        let overlayStyle = currentOverlayStyle
        guard overlayStyle != .off else {
            dismissIndicator()
            return
        }
        guard overlayStyle == .crab || state != .idle else {
            dismissIndicator()
            return
        }

        let crabHeight = currentCrabHeight()
        let initialFrame = initialIndicatorFrame(style: overlayStyle, crabHeight: crabHeight)
        writeOverlayPreviewLog(
            "showIndicator style=\(overlayStyle.rawValue) state=\(state) frame=\(NSStringFromRect(initialFrame))"
        )
        writeOverlaySnapshotIfRequested(style: overlayStyle, state: state, crabHeight: crabHeight)

        if indicatorPanel == nil {
            let panel = NSPanel(
                contentRect: initialFrame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.level = .statusBar
            panel.collectionBehavior = [
                .canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary,
            ]
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.ignoresMouseEvents = true

            let hostingView = NSHostingView(
                rootView: AppOverlayView(
                    style: overlayStyle,
                    state: state,
                    crabHeight: crabHeight
                )
            )
            hostingView.sizingOptions = .intrinsicContentSize
            hostingView.autoresizingMask = [.width, .height]
            hostingView.frame = NSRect(origin: .zero, size: initialFrame.size)
            hostingView.wantsLayer = true
            panel.contentView = hostingView

            indicatorPanel = panel
            indicatorHostingView = hostingView
        } else {
            indicatorHostingView?.rootView = AppOverlayView(
                style: overlayStyle,
                state: state,
                crabHeight: crabHeight
            )
        }

        positionIndicator(style: overlayStyle)
        resizeIndicatorContent()
        indicatorPanel?.orderFrontRegardless()
        writeOverlayPreviewLog(
            "ordered frame=\(NSStringFromRect(indicatorPanel?.frame ?? .zero)) visible=\(indicatorPanel?.isVisible ?? false)"
        )
    }

    private func updateIndicator(state: IndicatorState) {
        showIndicator(state: state)
    }

    private func finishIndicator() {
        let idleState = currentIdleIndicatorState()
        currentIndicatorState = idleState
        if currentOverlayStyle == .crab {
            showIndicator(state: idleState)
        } else {
            dismissIndicator()
        }
    }

    func refreshOverlay() {
        if appState != .idle {
            showIndicator(state: currentIndicatorState)
            return
        }

        if currentIndicatorState == .idle || currentIndicatorState.hasAttention {
            showIndicator(state: currentIdleIndicatorState())
            return
        }

        if currentOverlayStyle == .crab {
            showIndicator(state: currentIndicatorState)
        } else if currentIndicatorState == .idle {
            dismissIndicator()
        } else {
            showIndicator(state: currentIndicatorState)
        }
    }

    private func dismissIndicator() {
        hideIndicatorPanel()
        audioLevelCancellable?.cancel()
        audioLevelCancellable = nil
    }

    private func hideIndicatorPanel() {
        indicatorDismissTask?.cancel()
        indicatorDismissTask = nil
        indicatorPanel?.orderOut(nil)
    }

    private var visibleAppState: AppState {
        if appState == .recording {
            return .recording
        }
        if pendingTranscriptionCount > 0 {
            return .processing
        }
        if !transcriptionService.modelState.isReady {
            return .initializing(progress: transcriptionService.modelState.startupProgress)
        }
        return .idle
    }

    private func refreshMenuBarIcon() {
        updateMenuBarIcon(state: visibleAppState)
    }

    private var currentOverlayStyle: OverlayStyle {
        OverlayStyle(rawValue: UserDefaults.standard.string(forKey: Defaults.overlayStyle) ?? "")
            ?? .crab
    }

    private var modelIsReadyForOverlay: Bool {
        if ProcessInfo.processInfo.environment["SHOUTOUT_OVERLAY_PREVIEW"] != nil {
            return true
        }
        return transcriptionService.modelState.isReady
    }

    private func currentIdleIndicatorState() -> IndicatorState {
        if let shortcutUnavailableMessage {
            return .attention(message: shortcutUnavailableMessage)
        }

        if !permissions.hasAccessibility {
            return .attention(message: "Access off")
        }

        if !permissions.hasInputMonitoring {
            return .attention(message: "Input off")
        }

        if !permissions.hasMicrophone {
            return .attention(message: "Mic off")
        }

        return .idle
    }

    private func showTransientAttention(
        _ message: String,
        durationNanoseconds: UInt64 = 2_000_000_000
    ) {
        indicatorDismissTask?.cancel()
        indicatorDismissTask = nil
        showIndicator(state: .attention(message: message))
        indicatorDismissTask = Task {
            try? await Task.sleep(nanoseconds: durationNanoseconds)
            finishIndicator()
        }
    }

    private func showTranscriptionResultIndicator(
        _ state: IndicatorState,
        durationNanoseconds: UInt64 = 1_500_000_000
    ) {
        guard appState == .idle else { return }
        indicatorDismissTask?.cancel()
        indicatorDismissTask = nil
        updateIndicator(state: state)
        indicatorDismissTask = Task {
            try? await Task.sleep(nanoseconds: durationNanoseconds)
            if appState == .idle {
                finishIndicator()
            }
        }
    }

    private func requestedOverlayPreviewState() -> IndicatorState? {
        guard let rawState = ProcessInfo.processInfo.environment["SHOUTOUT_OVERLAY_PREVIEW"] else {
            return nil
        }

        switch rawState.lowercased() {
        case "idle":
            return .idle
        case "armed":
            return .armed
        case "recording":
            return .recording(level: 0.75)
        case "processing":
            return .processing
        case "done":
            return .done(text: "Done")
        case "attention":
            return .attention(message: "Mic off")
        default:
            return nil
        }
    }

    private func initialIndicatorFrame(style: OverlayStyle, crabHeight: CGFloat) -> NSRect {
        switch style {
        case .crab:
            guard let screen = NSScreen.main else {
                return NSRect(x: 0, y: 0, width: CrabOverlayLayout.width, height: crabHeight)
            }

            let screenFrame = screen.visibleFrame
            return NSRect(
                x: screenFrame.maxX - CrabOverlayLayout.width,
                y: screenFrame.minY + (screenFrame.height - crabHeight) / 2,
                width: CrabOverlayLayout.width,
                height: crabHeight
            )
        case .capsule:
            return NSRect(
                x: 0,
                y: 0,
                width: ClassicOverlayLayout.size.width,
                height: ClassicOverlayLayout.size.height
            )
        case .off:
            return NSRect(x: 0, y: 0, width: 1, height: 1)
        }
    }

    private func writeOverlayPreviewLog(_ message: String) {
        guard ProcessInfo.processInfo.environment["SHOUTOUT_OVERLAY_PREVIEW"] != nil else { return }

        let url = URL(fileURLWithPath: "/tmp/shoutout-overlay-preview.log")
        guard let data = "\(Date()) \(message)\n".data(using: .utf8) else { return }

        if FileManager.default.fileExists(atPath: url.path),
            let handle = try? FileHandle(forWritingTo: url)
        {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }

    private func writeOverlaySnapshotIfRequested(
        style: OverlayStyle,
        state: IndicatorState,
        crabHeight: CGFloat
    ) {
        guard
            let path = ProcessInfo.processInfo.environment["SHOUTOUT_OVERLAY_SNAPSHOT_PATH"]
        else { return }

        let snapshotSize = overlaySnapshotSize(style: style, crabHeight: crabHeight)
        let renderer = ImageRenderer(
            content: AppOverlayView(style: style, state: state, crabHeight: crabHeight)
                .frame(width: snapshotSize.width, height: snapshotSize.height)
        )
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2

        guard
            let image = renderer.nsImage,
            let tiffData = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiffData),
            let pngData = bitmap.representation(using: .png, properties: [:])
        else {
            writeOverlayPreviewLog("failed to render overlay snapshot")
            return
        }

        do {
            try pngData.write(to: URL(fileURLWithPath: path))
            writeOverlayPreviewLog("wrote overlay snapshot path=\(path)")
        } catch {
            writeOverlayPreviewLog("failed to write overlay snapshot path=\(path) error=\(error)")
        }
    }

    private func overlaySnapshotSize(style: OverlayStyle, crabHeight: CGFloat) -> CGSize {
        switch style {
        case .crab:
            return CGSize(width: CrabOverlayLayout.width, height: crabHeight)
        case .capsule:
            return ClassicOverlayLayout.size
        case .off:
            return CGSize(width: 1, height: 1)
        }
    }

    private func currentCrabHeight() -> CGFloat {
        guard let screen = NSScreen.main else {
            return 240
        }
        return max(screen.visibleFrame.height / 3, 220)
    }

    private func positionIndicator(style: OverlayStyle) {
        switch style {
        case .crab:
            positionCrabAtScreenEdge()
        case .capsule:
            positionIndicatorAtScreenBottom()
        case .off:
            break
        }
    }

    private func positionCrabAtScreenEdge() {
        guard let panel = indicatorPanel, let screen = NSScreen.main else { return }

        let screenFrame = screen.visibleFrame
        let height = currentCrabHeight()
        let width = CrabOverlayLayout.width
        let x = screenFrame.maxX - width
        let y = screenFrame.minY + (screenFrame.height - height) / 2

        panel.setFrame(
            NSRect(x: x, y: y, width: width, height: height),
            display: true
        )
    }

    private func positionIndicatorAtScreenBottom() {
        guard let panel = indicatorPanel,
            let hostingView = indicatorHostingView,
            let screen = NSScreen.main
        else { return }

        let contentSize = hostingView.fittingSize
        let screenFrame = screen.visibleFrame
        let x = screenFrame.midX - contentSize.width / 2
        let y = screenFrame.minY + 40  // 40pt above the bottom of the visible area

        panel.setFrame(
            NSRect(x: x, y: y, width: contentSize.width, height: contentSize.height),
            display: true
        )
    }

    private func resizeIndicatorContent() {
        guard let panel = indicatorPanel, let hostingView = indicatorHostingView else { return }
        hostingView.frame = NSRect(origin: .zero, size: panel.frame.size)
        panel.contentView?.needsDisplay = true
    }

    // MARK: - Main Menu

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        appMenu.addItem(
            NSMenuItem(
                title: "About ShoutOut",
                action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                keyEquivalent: ""))
        appMenu.addItem(.separator())
        appMenu.addItem(
            NSMenuItem(
                title: "Hide ShoutOut",
                action: #selector(NSApplication.hide(_:)),
                keyEquivalent: "h"))
        let hideOthers = NSMenuItem(
            title: "Hide Others",
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthers)
        appMenu.addItem(
            NSMenuItem(
                title: "Show All",
                action: #selector(NSApplication.unhideAllApplications(_:)),
                keyEquivalent: ""))
        appMenu.addItem(.separator())
        appMenu.addItem(
            NSMenuItem(
                title: "Quit ShoutOut",
                action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q"))

        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenuItem.submenu = editMenu
        editMenu.addItem(
            NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(
            NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(
            NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(
            NSMenuItem(
                title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))

        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: "Window")
        windowMenuItem.submenu = windowMenu
        windowMenu.addItem(
            NSMenuItem(
                title: "Close",
                action: #selector(NSWindow.performClose(_:)),
                keyEquivalent: "w"))
        windowMenu.addItem(
            NSMenuItem(
                title: "Minimize",
                action: #selector(NSWindow.performMiniaturize(_:)),
                keyEquivalent: "m"))

        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowMenu
    }

    // MARK: - Menu Bar

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = menuBarImage(for: .idle)
            button.action = #selector(statusBarButtonClicked)
        }
    }

    func updateMenuBarIcon(state: AppState) {
        guard let button = statusItem.button else { return }
        button.image = menuBarImage(for: state)
        button.imagePosition = .imageLeading
        button.title = menuBarTitle(for: state)
        button.toolTip = menuBarAccessibilityDescription(for: state)
        button.contentTintColor = state == .recording ? .systemRed : nil
    }

    private func menuBarImage(for state: AppState) -> NSImage? {
        if case .initializing = state {
            let image = NSImage(
                systemSymbolName: "arrow.down.circle", accessibilityDescription: "Preparing model")
            image?.isTemplate = true
            return image
        }

        if let image = crabMenuBarImage(
            named: state == .recording ? "recording-1" : "idle-1",
            accessibilityDescription: menuBarAccessibilityDescription(for: state)
        ) {
            return image
        }

        switch state {
        case .initializing:
            return nil
        case .idle:
            let image = NSImage(
                systemSymbolName: "waveform", accessibilityDescription: "ShoutOut")
            image?.isTemplate = true
            return image
        case .recording:
            let image = NSImage(
                systemSymbolName: "waveform", accessibilityDescription: "Recording")
            image?.isTemplate = false
            return image
        case .processing:
            let image = NSImage(
                systemSymbolName: "ellipsis.circle",
                accessibilityDescription: "Transcribing")
            image?.isTemplate = true
            return image
        }
    }

    private func menuBarTitle(for state: AppState) -> String {
        switch state {
        case .initializing(let progress):
            guard let progress else { return "" }
            return "\(Int(progress * 100))%"
        case .idle, .recording, .processing:
            return ""
        }
    }

    private func crabMenuBarImage(
        named name: String,
        accessibilityDescription: String
    ) -> NSImage? {
        guard
            let url = Bundle.main.url(
                forResource: name,
                withExtension: "png",
                subdirectory: "CrabSprites"
            ),
            let image = NSImage(contentsOf: url)
        else {
            return nil
        }

        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        image.accessibilityDescription = accessibilityDescription
        return image
    }

    private func menuBarAccessibilityDescription(for state: AppState) -> String {
        switch state {
        case .initializing(let progress):
            if let progress {
                return "Preparing ShoutOut model \(Int(progress * 100)) percent"
            }
            return "Preparing ShoutOut model"
        case .idle:
            return "ShoutOut"
        case .recording:
            return "Recording"
        case .processing:
            return "Transcribing"
        }
    }

    @objc private func statusBarButtonClicked(_ sender: NSStatusBarButton) {
        showContextMenu()
    }

    private func showContextMenu() {
        let menu = NSMenu()

        let todaySummary = usageStats.todaySummary
        let statsItem = NSMenuItem(
            title: "\(todaySummary.wordCount) words today · \(todaySummary.averageWordsPerMinute) WPM",
            action: nil,
            keyEquivalent: ""
        )
        statsItem.isEnabled = false
        menu.addItem(statsItem)

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(
            title: "Settings...", action: #selector(showSettingsAction), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: "Quit ShoutOut", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    // MARK: - Windows

    @objc private func showSettingsAction() {
        showSettings()
    }

    func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 440, height: 720),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "ShoutOut Settings"
            window.titlebarAppearsTransparent = true
            window.center()
            window.contentView = NSHostingView(
                rootView: SettingsView()
                    .environmentObject(transcriptionService)
                    .environmentObject(permissions)
                    .environmentObject(usageStats)
            )
            window.isReleasedWhenClosed = false
            window.delegate = self
            settingsWindow = window
        }

        NSApp.setActivationPolicy(.regular)
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showOnboarding() {
        if onboardingWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 500),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "Welcome to ShoutOut"
            window.center()
            window.contentView = NSHostingView(
                rootView: OnboardingView(onComplete: { [weak self] in
                    self?.closeOnboarding()
                })
                .environmentObject(self.transcriptionService)
                .environmentObject(self.permissions)
            )
            window.isReleasedWhenClosed = false
            window.delegate = self
            onboardingWindow = window
        }

        NSApp.setActivationPolicy(.regular)
        onboardingWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func closeOnboarding() {
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        onboardingWindow?.orderOut(nil)
        onboardingWindow?.close()
        onboardingWindow = nil
        if !UserDefaults.standard.bool(forKey: Defaults.showInDock) {
            NSApp.setActivationPolicy(.accessory)
        }
        setupHotkey()
    }

    func applyDockVisibilityPreference() {
        let showInDock = UserDefaults.standard.bool(forKey: Defaults.showInDock)
        let activeWindow = NSApp.keyWindow
        NSApp.setActivationPolicy(showInDock ? .regular : .accessory)
        Task { @MainActor in
            activeWindow?.makeKeyAndOrderFront(nil)
            NSApp.activate()
        }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}

// MARK: - NSWindowDelegate

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard let closedWindow = notification.object as? NSWindow else { return }

        if UserDefaults.standard.bool(forKey: Defaults.showInDock) { return }

        let otherWindow: NSWindow? =
            (closedWindow === settingsWindow) ? onboardingWindow : settingsWindow
        if otherWindow?.isVisible != true {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
