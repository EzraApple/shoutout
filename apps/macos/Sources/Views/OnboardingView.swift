import ShoutOutCore
import SwiftUI

struct OnboardingView: View {
    let onComplete: () -> Void

    @EnvironmentObject var transcription: TranscriptionService
    @EnvironmentObject var permissions: PermissionManager
    @AppStorage(Defaults.onboardingPage) private var savedPage = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var page: OnboardingPage {
        OnboardingPage.restore(
            savedPage: savedPage,
            legacyStep: UserDefaults.standard.integer(forKey: Defaults.onboardingStep)
        )
    }

    var body: some View {
        ZStack {
            ReviewTheme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                if page == .permissions {
                    header
                        .padding(.top, 42)
                        .layoutPriority(1)
                    permissionsChecklist
                } else {
                    header.frame(maxHeight: .infinity)
                }

                footer
            }
            .reviewWorkspaceSurface()
        }
        .frame(width: 560, height: 540)
        .onAppear {
            savedPage = page.rawValue
            permissions.refresh()
        }
        .onChange(of: permissions.hasAccessibility) { _, granted in
            if page == .permissions && granted {
                permissions.resolveInputMonitoringAfterAccessibility()
            }
        }
        .onChange(of: permissions.hasSpeechRecognition) { _, granted in
            guard granted, transcription.selectedBackend.requiresSpeechRecognitionPermission else { return }
            if case .error = transcription.modelState {
                Task { await transcription.loadModel() }
            }
        }
    }

    @ViewBuilder
    private var header: some View {
        switch page {
        case .welcome:
            pageHeading("Welcome to ShoutOut", detail: "Hold Fn to speak. Release to paste.") {
                ReviewCrabView(variant: "ocean", size: 50)
            }
        case .permissions:
            pageHeading("Set up ShoutOut", detail: "Reopen ShoutOut if macOS asks you to quit.") {
                Image(systemName: "lock.shield")
            }
        }
    }

    private func pageHeading<Icon: View>(
        _ title: String, detail: String, @ViewBuilder icon: () -> Icon
    ) -> some View {
        VStack(spacing: 14) {
            icon()
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(ReviewTheme.text)
                .frame(width: 64, height: 64)
                .onboardingSurface()
                .accessibilityHidden(true)
            VStack(spacing: 8) {
                ReviewPageHeader(title: title)
                    .accessibilityAddTraits(.isHeader)
                Text(detail)
                    .font(.system(size: 14))
                    .foregroundStyle(ReviewTheme.muted)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
    }

    private var permissionsChecklist: some View {
        ScrollView {
            VStack(spacing: 0) {
                OnboardingPermissionRow(icon: "mic", title: "Microphone", detail: "For your voice.", granted: permissions.hasMicrophone, actionTitle: "Allow") {
                    Task { _ = await permissions.requestMicrophone() }
                }
                OnboardingPermissionRow(icon: "hand.raised.fingers.spread", title: "Accessibility", detail: "To paste your words.", granted: permissions.hasAccessibility, actionTitle: "Open settings") {
                    permissions.requestAccessibility()
                }
                OnboardingPermissionRow(icon: "keyboard", title: "Input Monitoring", detail: permissions.hasAccessibility ? "To detect Fn in any app." : "Allow Accessibility first.", granted: permissions.hasInputMonitoring, actionTitle: "Open settings") {
                    permissions.requestInputMonitoring()
                }
                .disabled(!permissions.hasAccessibility && !permissions.hasInputMonitoring)

                if transcription.selectedBackend.requiresSpeechRecognitionPermission {
                    OnboardingPermissionRow(icon: "waveform", title: "Speech Recognition", detail: "For Apple dictation.", granted: permissions.hasSpeechRecognition, actionTitle: "Allow") {
                        Task { _ = await permissions.requestSpeechRecognition() }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .onboardingSurface()
        }
        .defaultScrollAnchor(.center, for: .alignment)
        .scrollBounceBehavior(.basedOnSize)
        .padding(.horizontal, 32)
        .padding(.top, 8)
        .onAppear {
            permissions.resolveInputMonitoringAfterAccessibility()
            permissions.beginPollingForPermissionChanges()
        }
    }

    private var footer: some View {
        VStack(spacing: 14) {
            if page == .permissions {
                modelStatusView
                    .font(.system(size: 12, weight: .semibold))
                    .frame(height: 60, alignment: .bottom)
            }

            OnboardingPageIndicator(
                current: OnboardingPage.allCases.firstIndex(of: page) ?? 0,
                total: OnboardingPage.allCases.count
            )

            HStack(spacing: 12) {
                if page != .welcome {
                    Button("Back") { showPage(.welcome) }
                        .buttonStyle(OnboardingNavigationButtonStyle(primary: false))
                        .frame(width: 96)
                }

                Button(forwardTitle, action: advance)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(OnboardingNavigationButtonStyle(primary: true))
                    .frame(width: 200)
                    .disabled(page == .permissions && !setupIsReady)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
        .padding(.top, 12)
        .padding(.bottom, 28)
        .layoutPriority(1)
    }

    private var forwardTitle: String {
        switch page {
        case .welcome: "Get started"
        case .permissions: "Start dictating"
        }
    }

    private func advance() {
        switch page {
        case .welcome: showPage(.permissions)
        case .permissions:
            permissions.refresh()
            if setupIsReady { onComplete() }
        }
    }

    private var setupIsReady: Bool {
        permissions.hasMicrophone && permissions.hasAccessibility && permissions.hasInputMonitoring
            && (!transcription.selectedBackend.requiresSpeechRecognitionPermission || permissions.hasSpeechRecognition)
            && transcription.modelState == .ready
    }

    @ViewBuilder
    private var modelStatusView: some View {
        switch transcription.modelState {
        case .ready:
            Label("On-device dictation is ready", systemImage: "checkmark.circle.fill")
                .foregroundStyle(OnboardingTheme.granted)
        case .unloaded, .loading:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Preparing on-device dictation…")
            }
            .foregroundStyle(ReviewTheme.muted)
        case .downloading(let progress):
            VStack(spacing: 6) {
                Text("Preparing on-device dictation · \(Int(progress * 100))%")
                    .foregroundStyle(ReviewTheme.muted)
                ModelProgressBar(progress: progress).frame(width: 220)
            }
        case .error(let message):
            HStack(spacing: 12) {
                ViewThatFits(in: .vertical) {
                    Text(message).fixedSize(horizontal: false, vertical: true)
                    ScrollView { Text(message).frame(maxWidth: .infinity, alignment: .leading) }
                }
                .foregroundStyle(OnboardingTheme.warning)
                .frame(maxHeight: 56)
                Button("Retry") { Task { await transcription.loadModel() } }
                    .buttonStyle(OnboardingSecondaryButtonStyle())
                    .fixedSize()
            }
        }
    }

    private func showPage(_ page: OnboardingPage) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
            savedPage = page.rawValue
        }
    }
}

private struct OnboardingPermissionRow: View {
    let icon: String
    let title: String
    let detail: String
    let granted: Bool
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(ReviewTheme.text)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(ReviewTheme.text)
                Text(detail)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ReviewTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if granted {
                Label("Granted", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(OnboardingTheme.granted)
            } else {
                Button(actionTitle, action: action)
                    .buttonStyle(OnboardingSecondaryButtonStyle())
                    .accessibilityLabel("\(actionTitle) for \(title)")
            }
        }
        .padding(.vertical, 5)
    }
}

private struct OnboardingSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(isEnabled ? ReviewTheme.text : ReviewTheme.subtle)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .onboardingSurface(fill: configuration.isPressed ? ReviewTheme.pressedFill : ReviewTheme.raised)
    }
}

private struct OnboardingNavigationButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    let primary: Bool

    func makeBody(configuration: Configuration) -> some View {
        let foreground = primary ? ReviewTheme.background : ReviewTheme.text
        let fill = if !isEnabled {
            ReviewTheme.panel
        } else if primary {
            ReviewTheme.accent.opacity(configuration.isPressed ? 0.8 : 1)
        } else {
            configuration.isPressed ? ReviewTheme.pressedFill : ReviewTheme.raised
        }

        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(isEnabled ? foreground : ReviewTheme.subtle)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .onboardingSurface(fill: fill)
    }
}

private struct OnboardingPageIndicator: View {
    let current: Int
    let total: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { index in
                Capsule()
                    .fill(index == current ? ReviewTheme.accent : ReviewTheme.subtle.opacity(0.4))
                    .frame(width: index == current ? 18 : 6, height: 6)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(current + 1) of \(total)")
    }
}

private enum OnboardingTheme {
    static let granted = Color(red: 0.46, green: 0.82, blue: 0.61)
    static let warning = Color(red: 0.99, green: 0.70, blue: 0.39)
}

private extension View {
    func onboardingSurface(fill: Color = ReviewTheme.panel) -> some View {
        let shape = RoundedRectangle(cornerRadius: ReviewTheme.navigationRadius)
        return background(fill, in: shape)
            .overlay(shape.strokeBorder(ReviewTheme.line).allowsHitTesting(false))
    }
}
