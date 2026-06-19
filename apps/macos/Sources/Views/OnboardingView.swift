import AppKit
import SwiftUI

// MARK: - Onboarding View

struct OnboardingView: View {
    let onComplete: () -> Void

    @EnvironmentObject var transcription: TranscriptionService
    @EnvironmentObject var permissions: PermissionManager
    @AppStorage(Defaults.onboardingStep) private var step = 0

    private let totalSteps = 7

    var body: some View {
        ZStack {
            OnboardingBackground()

            VStack(spacing: 0) {
                ZStack {
                    switch step {
                    case 0: welcomeStep.transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
                    case 1: microphoneStep.transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
                    case 2: speechRecognitionStep.transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
                    case 3: accessibilityStep.transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
                    case 4: inputMonitoringStep.transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
                    case 5: modelStep.transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
                    case 6: doneStep.transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
                    default: EmptyView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(.spring(response: 0.45, dampingFraction: 0.85), value: step)

                if step > 0 && step < totalSteps - 1 {
                    OnboardingPageIndicator(current: step, total: totalSteps)
                        .padding(.bottom, 20)
                }
            }
        }
        .frame(width: 560, height: 540)
        .onAppear {
            if step < 0 || step >= totalSteps {
                step = 0
            }
        }
    }

    // MARK: - Step 0: Welcome

    private var welcomeStep: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                WelcomeIcon()

                VStack(spacing: 8) {
                    Text("Welcome to ShoutOut")
                        .font(.system(size: 34, weight: .heavy, design: .rounded))
                        .foregroundStyle(OnboardingTheme.ink)

                    Text("Local dictation for macOS — let's get you set up")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(OnboardingTheme.muted)
                }
            }

            Spacer()

            OnboardingPillButton("Get Started") {
                withAnimation { step = 1 }
            }
            .padding(.bottom, 8)
        }
        .padding(.horizontal, 48)
        .padding(.vertical, 40)
    }

    // MARK: - Step 1: Microphone

    private var microphoneStep: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                OnboardingStepIcon(systemName: "mic", background: OnboardingTheme.coral)

                VStack(spacing: 8) {
                    Text("Microphone")
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                        .foregroundStyle(OnboardingTheme.ink)

                    Text("ShoutOut needs your microphone to hear your voice for dictation")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(OnboardingTheme.muted)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                OnboardingPermissionBadge(granted: permissions.hasMicrophone)
            }

            Spacer()

            VStack(spacing: 12) {
                if permissions.hasMicrophone {
                    OnboardingPillButton("Continue") {
                        withAnimation { step = 2 }
                    }
                } else {
                    OnboardingPillButton("Grant Permission") {
                        Task { await permissions.requestMicrophone() }
                    }

                    Button(action: { withAnimation { step = 2 } }) {
                        Text("Skip for now")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(OnboardingTheme.muted)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 8)
        }
        .padding(.horizontal, 48)
        .padding(.vertical, 40)
    }

    // MARK: - Step 2: Speech Recognition

    private var speechRecognitionStep: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                OnboardingStepIcon(systemName: "waveform", background: OnboardingTheme.panelMint)

                VStack(spacing: 8) {
                    Text("Speech Recognition")
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                        .foregroundStyle(OnboardingTheme.ink)

                    Text("Required for Apple's local transcription engines")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(OnboardingTheme.muted)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                OnboardingPermissionBadge(granted: permissions.hasSpeechRecognition)
            }

            Spacer()

            VStack(spacing: 12) {
                if permissions.hasSpeechRecognition {
                    OnboardingPillButton("Continue") {
                        withAnimation { step = 3 }
                    }
                } else {
                    OnboardingPillButton("Grant Permission") {
                        Task { await permissions.requestSpeechRecognition() }
                    }

                    Button(action: { withAnimation { step = 3 } }) {
                        Text("Skip for now")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(OnboardingTheme.muted)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 8)
        }
        .padding(.horizontal, 48)
        .padding(.vertical, 40)
    }

    // MARK: - Step 3: Accessibility

    private var accessibilityStep: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                OnboardingStepIcon(
                    systemName: "hand.raised.fingers.spread",
                    background: OnboardingTheme.panelLilac
                )

                VStack(spacing: 8) {
                    Text("Accessibility")
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                        .foregroundStyle(OnboardingTheme.ink)

                    Text("Required for the global shortcut and pasting text into other apps")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(OnboardingTheme.muted)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                OnboardingPermissionBadge(granted: permissions.hasAccessibility)
            }

            Spacer()

            VStack(spacing: 12) {
                if permissions.hasAccessibility {
                    OnboardingPillButton("Continue") {
                        withAnimation { step = 4 }
                    }
                } else {
                    OnboardingPillButton("Grant Permission") {
                        permissions.requestAccessibility()
                    }

                    Button(action: { withAnimation { step = 4 } }) {
                        Text("Skip for now")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(OnboardingTheme.muted)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 8)
        }
        .padding(.horizontal, 48)
        .padding(.vertical, 40)
    }

    // MARK: - Step 4: Input Monitoring

    private var inputMonitoringStep: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                OnboardingStepIcon(systemName: "keyboard", background: OnboardingTheme.panelBlue)

                VStack(spacing: 8) {
                    Text("Input Monitoring")
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                        .foregroundStyle(OnboardingTheme.ink)

                    Text("Required to detect your shortcut while other apps are focused")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(OnboardingTheme.muted)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                OnboardingPermissionBadge(granted: permissions.hasInputMonitoring)
            }

            Spacer()

            VStack(spacing: 12) {
                if permissions.hasInputMonitoring {
                    OnboardingPillButton("Continue") {
                        withAnimation { step = 5 }
                    }
                } else {
                    OnboardingPillButton("Grant Permission") {
                        permissions.requestInputMonitoring()
                    }

                    Button(action: { withAnimation { step = 5 } }) {
                        Text("Skip for now")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(OnboardingTheme.muted)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 8)
        }
        .padding(.horizontal, 48)
        .padding(.vertical, 40)
    }

    // MARK: - Step 5: Model Download

    private var modelStep: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                OnboardingStepIcon(systemName: "cpu", background: OnboardingTheme.panelMint)

                VStack(spacing: 8) {
                    Text("Dictation Setup")
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                        .foregroundStyle(OnboardingTheme.ink)

                    modelStatusView
                }
            }

            Spacer()

            if transcription.modelState == .ready {
                OnboardingPillButton("Continue") {
                    withAnimation { step = 6 }
                }
                .padding(.bottom, 8)
            } else if case .error = transcription.modelState {
                OnboardingPillButton("Retry") {
                    Task { await transcription.loadModel() }
                }
                .padding(.bottom, 8)
            }
        }
        .padding(.horizontal, 48)
        .padding(.vertical, 40)
        .onAppear {
            if transcription.modelState == .unloaded {
                Task { await transcription.loadModel() }
            }
        }
    }

    @ViewBuilder
    private var modelStatusView: some View {
        switch transcription.modelState {
        case .ready:
            VStack(spacing: 12) {
                Text("\(transcription.selectedPreset.title) mode is ready")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(OnboardingTheme.muted)

                OnboardingPermissionBadge(granted: true)
            }
        case .loading:
            VStack(spacing: 12) {
                Text("Preparing dictation...")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(OnboardingTheme.muted)
                ModelProgressBar(progress: 1)
                    .frame(width: 220)
            }
        case .downloading(let progress):
            VStack(spacing: 12) {
                Text("Downloading local dictation model \(Int(progress * 100))%")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(OnboardingTheme.muted)
                ModelProgressBar(progress: progress)
                    .frame(width: 220)
            }
        case .error(let msg):
            VStack(spacing: 8) {
                Text(msg)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(OnboardingTheme.warning)
                    .multilineTextAlignment(.center)
            }
        case .unloaded:
            Text("Preparing...")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(OnboardingTheme.muted)
        }
    }

    // MARK: - Step 6: Done

    private var doneStep: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                DoneCheckmark()

                VStack(spacing: 8) {
                    Text("You're all set")
                        .font(.system(size: 34, weight: .heavy, design: .rounded))
                        .foregroundStyle(OnboardingTheme.ink)

                    Text("Hold your shortcut to dictate, release to paste")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(OnboardingTheme.muted)
                }

                VStack(spacing: 2) {
                    OnboardingSummaryRow(
                        icon: "mic",
                        title: "Microphone",
                        granted: permissions.hasMicrophone
                    )
                    OnboardingSummaryRow(
                        icon: "waveform",
                        title: "Speech Recognition",
                        granted: permissions.hasSpeechRecognition
                    )
                    OnboardingSummaryRow(
                        icon: "hand.raised.fingers.spread",
                        title: "Accessibility",
                        granted: permissions.hasAccessibility
                    )
                    OnboardingSummaryRow(
                        icon: "keyboard",
                        title: "Input Monitoring",
                        granted: permissions.hasInputMonitoring
                    )
                    OnboardingSummaryRow(
                        icon: "cpu",
                        title: "Dictation: \(transcription.selectedPreset.title)",
                        granted: transcription.modelState == .ready
                    )
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .onboardingPixelBox(background: OnboardingTheme.panel, border: OnboardingTheme.ink)
            }

            Spacer()

            OnboardingPillButton("Start Dictating") {
                onComplete()
            }
            .padding(.bottom, 8)
        }
        .padding(.horizontal, 48)
        .padding(.vertical, 40)
    }
}

// MARK: - Shared Components

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

private struct DoneCheckmark: View {
    @State private var appeared = false

    var body: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 26, weight: .semibold))
            .foregroundStyle(OnboardingTheme.ink)
            .frame(width: 64, height: 64)
            .onboardingPixelBox(
                background: OnboardingTheme.panelMint,
                border: OnboardingTheme.ink,
                shadow: OnboardingTheme.teal,
                shadowOffset: CGSize(width: 5, height: 5)
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

private struct OnboardingPermissionBadge: View {
    let granted: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(granted ? OnboardingTheme.teal : OnboardingTheme.warning)
                .frame(width: 8, height: 8)
            Text(granted ? "Granted" : "Not Granted")
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(OnboardingTheme.ink)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .onboardingPixelBox(
            background: granted ? OnboardingTheme.panelMint : OnboardingTheme.panel,
            border: OnboardingTheme.ink
        )
        .animation(.easeOut(duration: 0.25), value: granted)
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

private struct OnboardingSummaryRow: View {
    let icon: String
    let title: String
    let granted: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(OnboardingTheme.muted)
                .frame(width: 20)

            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(OnboardingTheme.ink)

            Spacer()

            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle")
                .font(.system(size: 14))
                .foregroundStyle(granted ? OnboardingTheme.teal : OnboardingTheme.warning)
        }
        .padding(.vertical, 6)
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
