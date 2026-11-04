import AppKit
import SwiftUI

struct ReviewIndicatorPreview: View {
    let style: OverlayStyle
    let anchor: IndicatorAnchor
    let customHex: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.controlActiveState) private var controlActiveState
    @State private var isVisible = false
    @State private var appIsActive = NSApp.isActive
    @State private var appIsHidden = NSApp.isHidden
    @State private var phase = PreviewPhase.recording

    private enum PreviewPhase: String {
        case recording = "Recording"
        case processing = "Processing"
        case done = "Done"
        case idle = "Idle"

        var state: IndicatorState {
            switch self {
            case .recording: .recording(level: 0.55, mode: .hold)
            case .processing: .processing
            case .done: .done(text: "")
            case .idle: .idle
            }
        }

        var duration: Duration {
            switch self {
            case .recording: .seconds(2.5)
            case .processing: .seconds(0.8)
            case .done: .seconds(1.2)
            case .idle: .seconds(1.5)
            }
        }

        var next: Self {
            switch self {
            case .recording: .processing
            case .processing: .done
            case .done: .idle
            case .idle: .recording
            }
        }
    }

    private var shouldLoop: Bool {
        isVisible && appIsActive && !appIsHidden
            && controlActiveState == .key && !reduceMotion
    }

    private var styleName: String {
        switch style {
        case .crab, .off: "Crab"
        case .glass: "Glass"
        case .capsule: "Classic"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Preview")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ReviewTheme.muted)

            GeometryReader { geometry in
                screenCrop(size: geometry.size)
            }
            .aspectRatio(16.0 / 10.0, contentMode: .fit)
            .frame(maxHeight: 260)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(styleName) indicator preview at the \(anchor.rawValue) edge")

            Text("Preview · \(reduceMotion ? PreviewPhase.recording.rawValue : phase.rawValue)")
                .font(.system(size: 13))
                .foregroundStyle(ReviewTheme.muted)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            isVisible = true
            appIsActive = NSApp.isActive
            appIsHidden = NSApp.isHidden
        }
        .onDisappear { isVisible = false }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            appIsActive = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            appIsActive = false
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didHideNotification)) { _ in
            appIsHidden = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didUnhideNotification)) { _ in
            appIsHidden = false
        }
        .task(id: shouldLoop) {
            phase = .recording
#if DEBUG
            RuntimeLog.write(
                "indicator preview lifecycle visible=\(isVisible) appActive=\(appIsActive) "
                    + "appHidden=\(appIsHidden) control=\(String(describing: controlActiveState)) "
                    + "reduceMotion=\(reduceMotion) shouldLoop=\(shouldLoop)"
            )
#endif
            guard shouldLoop else { return }
#if DEBUG
            let taskID = UUID().uuidString
            RuntimeLog.write("indicator preview loop started id=\(taskID)")
            defer { RuntimeLog.write("indicator preview loop stopped id=\(taskID)") }
#endif
            while !Task.isCancelled {
                let current = phase
                try? await Task.sleep(for: current.duration)
                guard !Task.isCancelled else { return }
                phase = current.next
            }
        }
    }

    private func screenCrop(size: CGSize) -> some View {
        let display = CGRect(origin: .zero, size: size)
        let indicatorFrame = anchor.frame(in: display, style: style, crabHeight: 220)
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: ReviewTheme.navigationRadius)
                .fill(Color(white: 0.20))

            if anchor == .top {
                Rectangle()
                    .fill(ReviewTheme.line.opacity(0.45))
                    .frame(height: 12)
                    .overlay(alignment: .leading) {
                        HStack(spacing: 4) {
                            Circle().frame(width: 3, height: 3)
                            Circle().frame(width: 3, height: 3)
                        }
                        .foregroundStyle(ReviewTheme.muted.opacity(0.45))
                        .padding(.leading, 8)
                    }
            }

            AppOverlayView(
                style: style,
                state: reduceMotion ? PreviewPhase.recording.state : phase.state,
                crabHeight: 220,
                customTint: customHex.flatMap(ReviewTheme.nativeColor(hex:)),
                reduceMotionOverride: reduceMotion || !shouldLoop,
                anchor: anchor
            )
            .allowsHitTesting(false)
            .position(x: indicatorFrame.midX, y: size.height - indicatorFrame.midY)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: ReviewTheme.navigationRadius))
        .overlay(RoundedRectangle(cornerRadius: ReviewTheme.navigationRadius).stroke(ReviewTheme.line))
    }
}
