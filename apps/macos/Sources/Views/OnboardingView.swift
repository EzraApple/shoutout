import AppKit
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
            OnboardingBackground()
            VStack(spacing: 0) {
                Group {
                    switch page {
                    case .welcome: welcomePage
                    case .howItWorks: howItWorksPage
                    case .permissions: permissionsPage
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                OnboardingPageIndicator(
                    current: OnboardingPage.allCases.firstIndex(of: page) ?? 0,
                    total: OnboardingPage.allCases.count
                )
                .padding(.bottom, 20)
            }
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

    private var welcomePage: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 24) {
                WelcomeIcon()
                VStack(spacing: 10) {
                    Text("Welcome to ShoutOut")
                        .font(.system(size: 34, weight: .heavy, design: .rounded))
                        .foregroundStyle(OnboardingTheme.ink)
                    Text("Instant transcription. Right where you type.")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(OnboardingTheme.muted)
                }
            }
            Spacer()
            OnboardingPillButton("Get Started") { showPage(.howItWorks) }
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 32)
    }

    private var howItWorksPage: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 0)
            OnboardingStepIcon(systemName: "keyboard", background: OnboardingTheme.panelBlue)
            Text("How ShoutOut works")
                .font(.system(size: 26, weight: .heavy, design: .rounded))
                .foregroundStyle(OnboardingTheme.ink)
            VStack(spacing: 18) {
                OnboardingInstructionRow(icon: "fn", title: "Hold Fn", detail: "Place your cursor where you want to type.")
                OnboardingInstructionRow(icon: "waveform", title: "Speak naturally", detail: "ShoutOut transcribes on your Mac.")
                OnboardingInstructionRow(icon: "text.cursor", title: "Release to paste", detail: "Your words appear at your cursor.")
            }
            Text("Double-press Fn for hands-free dictation.\nPress Fn again to finish.")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(OnboardingTheme.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            VStack(spacing: 12) {
                OnboardingPillButton("Continue") { showPage(.permissions) }
                backButton(to: .welcome)
            }
        }
        .padding(.horizontal, 48)
        .padding(.vertical, 20)
    }

    private var permissionsPage: some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                Text("Set up ShoutOut")
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .foregroundStyle(OnboardingTheme.ink)
                Text("Allow access below. If macOS asks you to quit,\nreopen ShoutOut to continue here.")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(OnboardingTheme.muted)
                    .multilineTextAlignment(.center)
            }

            ScrollView {
                VStack(spacing: 0) {
                    OnboardingPermissionRow(icon: "mic", title: "Microphone", detail: "Hear your voice while you dictate.", granted: permissions.hasMicrophone, actionTitle: "Allow") {
                        Task { _ = await permissions.requestMicrophone() }
                    }
                    OnboardingPermissionRow(icon: "hand.raised.fingers.spread", title: "Accessibility", detail: "Paste your words into other apps.", granted: permissions.hasAccessibility, actionTitle: "Open Settings") {
                        permissions.openAccessibilitySettings()
                    }
                    OnboardingPermissionRow(icon: "keyboard", title: "Input Monitoring", detail: permissions.hasAccessibility ? "Use Fn while other apps are focused." : "Allow Accessibility first. We’ll check this for you.", granted: permissions.hasInputMonitoring, actionTitle: "Open Settings") {
                        permissions.requestInputMonitoring()
                    }
                    .disabled(!permissions.hasAccessibility && !permissions.hasInputMonitoring)

                    if transcription.selectedBackend.requiresSpeechRecognitionPermission {
                        OnboardingPermissionRow(icon: "waveform", title: "Speech Recognition", detail: "Use Apple’s on-device dictation.", granted: permissions.hasSpeechRecognition, actionTitle: "Allow") {
                            Task { _ = await permissions.requestSpeechRecognition() }
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .onboardingPixelBox(background: OnboardingTheme.panel)
                .padding(2)

                modelStatusView
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.top, 12)
            }
            .scrollBounceBehavior(.basedOnSize)

            VStack(spacing: 12) {
                OnboardingPillButton("Start Dictating") {
                    permissions.refresh()
                    if setupIsReady { onComplete() }
                }
                .disabled(!setupIsReady)
                .opacity(setupIsReady ? 1 : 0.45)
                backButton(to: .howItWorks)
            }
        }
        .padding(.horizontal, 32)
        .padding(.top, 24)
        .padding(.bottom, 16)
        .onAppear {
            permissions.resolveInputMonitoringAfterAccessibility()
            permissions.beginPollingForPermissionChanges()
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
            .foregroundStyle(OnboardingTheme.muted)
        case .downloading(let progress):
            VStack(spacing: 6) {
                Text("Preparing on-device dictation · \(Int(progress * 100))%")
                    .foregroundStyle(OnboardingTheme.muted)
                ModelProgressBar(progress: progress).frame(width: 220)
            }
        case .error(let message):
            VStack(spacing: 8) {
                Text(message)
                    .foregroundStyle(OnboardingTheme.warning)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Retry") { Task { await transcription.loadModel() } }
                    .buttonStyle(OnboardingSecondaryButtonStyle())
            }
        }
    }

    private func showPage(_ page: OnboardingPage) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
            savedPage = page.rawValue
        }
    }

    private func backButton(to page: OnboardingPage) -> some View {
        Button("Back") { showPage(page) }
            .buttonStyle(.plain)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(OnboardingTheme.muted)
    }
}

private struct OnboardingInstructionRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 15, weight: .bold))
                Text(detail)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(OnboardingTheme.muted)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(OnboardingTheme.ink)
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
                .foregroundStyle(OnboardingTheme.ink)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(OnboardingTheme.ink)
                Text(detail)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(OnboardingTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if granted {
                Label("Granted", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(OnboardingTheme.granted)
            } else {
                Button(actionTitle, action: action)
                    .buttonStyle(OnboardingSecondaryButtonStyle())
                    .accessibilityLabel("\(actionTitle) for \(title)")
            }
        }
        .padding(.vertical, 6)
    }
}

private struct OnboardingSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(OnboardingTheme.ink.opacity(isEnabled ? 1 : 0.45))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .onboardingPixelBox(
                background: configuration.isPressed ? OnboardingTheme.panelMint : OnboardingTheme.panelBlue
            )
            .opacity(isEnabled ? 1 : 0.5)
    }
}

private struct OnboardingBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    OnboardingTheme.background,
                    Color(red: 0.90, green: 0.96, blue: 1.00),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            GridPattern()
                .stroke(OnboardingTheme.ink.opacity(0.08), lineWidth: 1)
        }
        .ignoresSafeArea()
    }
}

private struct OnboardingPillButton: View {
    let title: String
    let action: () -> Void

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(OnboardingTheme.ink)
                .frame(height: 44)
                .frame(maxWidth: .infinity)
                .onboardingPixelBox(
                    background: OnboardingTheme.coral,
                    border: OnboardingTheme.ink,
                    shadow: OnboardingTheme.ink,
                    shadowOffset: CGSize(width: 4, height: 4)
                )
        }
        .buttonStyle(.plain)
    }
}

private struct WelcomeIcon: View {
    @State private var appeared = false

    var body: some View {
        ZStack {
            if let image = NSImage.onboardingCrabSprite(named: "idle-1") {
                Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 82, height: 72)
            } else {
                Image(systemName: "waveform")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(OnboardingTheme.ink)
            }
        }
        .frame(width: 112, height: 94)
        .onboardingPixelBox(
            background: OnboardingTheme.panelBlue,
            border: OnboardingTheme.ink,
            shadow: OnboardingTheme.coral,
            shadowOffset: CGSize(width: 6, height: 6)
        )
            .scaleEffect(appeared ? 1.0 : 0.3)
            .opacity(appeared ? 1.0 : 0.0)
            .onAppear {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.6).delay(0.15)) {
                    appeared = true
                }
            }
    }
}

private struct OnboardingPageIndicator: View {
    let current: Int
    let total: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { index in
                Rectangle()
                    .fill(index == current ? OnboardingTheme.coral : OnboardingTheme.panel)
                    .frame(width: index == current ? 18 : 8, height: 8)
                    .overlay(Rectangle().stroke(OnboardingTheme.ink, lineWidth: 1))
                    .animation(.easeOut(duration: 0.2), value: current)
            }
        }
    }
}

private struct OnboardingStepIcon: View {
    let systemName: String
    let background: Color

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 28, weight: .semibold))
            .foregroundStyle(OnboardingTheme.ink)
            .frame(width: 64, height: 64)
            .onboardingPixelBox(
                background: background,
                border: OnboardingTheme.ink,
                shadow: OnboardingTheme.ink,
                shadowOffset: CGSize(width: 4, height: 4)
            )
    }
}

private enum OnboardingTheme {
    static let granted = Color(red: 0.08, green: 0.43, blue: 0.24)
    static let ink = Color(red: 0.03, green: 0.09, blue: 0.18)
    static let muted = Color(red: 0.25, green: 0.33, blue: 0.46)
    static let background = Color(red: 0.78, green: 0.87, blue: 0.97)
    static let panel = Color(red: 0.97, green: 0.99, blue: 1.00)
    static let panelBlue = Color(red: 0.66, green: 0.84, blue: 1.00)
    static let panelMint = Color(red: 0.56, green: 0.85, blue: 0.86)
    static let panelLilac = Color(red: 0.75, green: 0.82, blue: 1.00)
    static let coral = Color(red: 1.00, green: 0.44, blue: 0.41)
    static let teal = Color(red: 0.08, green: 0.59, blue: 0.68)
    static let warning = Color(red: 0.74, green: 0.35, blue: 0.02)
}

private struct GridPattern: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let spacing: CGFloat = 42

        var x = rect.minX
        while x <= rect.maxX {
            path.move(to: CGPoint(x: x, y: rect.minY))
            path.addLine(to: CGPoint(x: x, y: rect.maxY))
            x += spacing
        }

        var y = rect.minY
        while y <= rect.maxY {
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
            y += spacing
        }

        return path
    }
}

private extension NSImage {
    static func onboardingCrabSprite(named name: String) -> NSImage? {
        guard let url = Bundle.main.url(
            forResource: name,
            withExtension: "png",
            subdirectory: "CrabSpriteVariants/ocean"
        ) ?? Bundle.main.url(
            forResource: name,
            withExtension: "png",
            subdirectory: "CrabSprites"
        ) else {
            return nil
        }

        return NSImage(contentsOf: url)
    }
}

private extension View {
    func onboardingPixelBox(
        background: Color,
        border: Color = OnboardingTheme.ink,
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
}
