import AppKit
import SwiftUI

struct ReviewTooltipAnchors: PreferenceKey {
    static var defaultValue: [UUID: Anchor<CGRect>] { [:] }
    static func reduce(value: inout [UUID: Anchor<CGRect>], nextValue: () -> [UUID: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}

@MainActor final class ReviewTooltipController: ObservableObject {
    enum Placement { case rail, action }
    struct Tip {
        let id: UUID
        let title: String
        let hint: String?
        let shortcut: String?
        let placement: Placement
    }

    @Published private(set) var tip: Tip?
    @Published private(set) var keyboardNavigation = false
    private var pending: Task<Void, Never>?
    private var pendingID: UUID?
    private var lastShown = Date.distantPast
    private var eventMonitor: Any?

    func request(_ tip: Tip, immediate: Bool = false) {
        pending?.cancel()
        pendingID = tip.id
        let delay = immediate || Date().timeIntervalSince(lastShown) < 0.5 ? 0 : 400
        pending = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(delay))
            guard !Task.isCancelled else { return }
            self.tip = tip
            lastShown = Date()
        }
    }

    func showSuccess(_ tip: Tip) {
        request(tip, immediate: true)
        pending?.cancel()
        self.tip = tip
        lastShown = Date()
        pending = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            self.tip = nil
        }
    }

    func dismiss(_ id: UUID? = nil) {
        if id == nil || pendingID == id {
            pending?.cancel()
            pendingID = nil
        }
        if let tip, id == nil || tip.id == id {
            lastShown = Date()
            self.tip = nil
        }
    }

    func startMonitoring() {
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            if event.type == .leftMouseDown || event.type == .rightMouseDown {
                if self?.keyboardNavigation == true { self?.keyboardNavigation = false }
            } else if event.type == .keyDown && event.keyCode == 48 && self?.keyboardNavigation == false {
                self?.keyboardNavigation = true
            }
            let dismissesVisibleTip = event.type == .keyDown && event.keyCode == 53 && self?.tip != nil
            if event.type != .keyDown || event.keyCode == 53 {
                self?.dismiss()
            }
            return dismissesVisibleTip ? nil : event
        }
    }

    func stopMonitoring() {
        dismiss()
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = nil
    }
}

struct ReviewTooltippedButton<Label: View>: View {
    @EnvironmentObject private var tooltips: ReviewTooltipController
    @Environment(\.isEnabled) private var isEnabled
    @FocusState private var focused: Bool
    @State private var id = UUID()
    @State private var suppressed = false
    let title: String
    var hint: String? = nil
    var shortcut: String? = nil
    var placement: ReviewTooltipController.Placement = .action
    var successMessage: String? = nil
    var feedbackRevision = 0
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button(action: activate, label: label)
        .focusable()
        .focused($focused)
        .onKeyPress(.space) { activate(); return .handled }
        .onKeyPress(.return) { activate(); return .handled }
        .focusEffectDisabled()
        .overlay {
            RoundedRectangle(cornerRadius: ReviewTheme.navigationRadius)
                .strokeBorder(focused && tooltips.keyboardNavigation ? ReviewTheme.muted : .clear, lineWidth: 1)
                .allowsHitTesting(false)
        }
        .accessibilityLabel(title)
        .accessibilityHint(hint ?? "")
        .anchorPreference(key: ReviewTooltipAnchors.self, value: .bounds) { [id: $0] }
        .onHover { inside in
            if inside { requestTooltip() }
            else { suppressed = false; tooltips.dismiss(id) }
        }
        .onChange(of: focused) { _, value in
            if value && tooltips.keyboardNavigation { suppressed = false; requestTooltip(immediate: true) }
            else { tooltips.dismiss(id) }
        }
        .onChange(of: feedbackRevision) { _, _ in
            if let successMessage {
                tooltips.showSuccess(.init(id: id, title: successMessage, hint: nil, shortcut: nil, placement: placement))
            }
        }
        .onDisappear { tooltips.dismiss(id) }
    }

    private func activate() {
        guard isEnabled else { return }
        suppressed = true
        tooltips.dismiss()
        action()
    }

    private func requestTooltip(immediate: Bool = false) {
        guard isEnabled, !suppressed else { return }
        tooltips.request(.init(id: id, title: title, hint: hint, shortcut: shortcut, placement: placement), immediate: immediate)
    }
}

struct ReviewTooltipOverlay: View {
    @ObservedObject var controller: ReviewTooltipController
    let anchors: [UUID: Anchor<CGRect>]

    var body: some View {
        GeometryReader { geometry in
            if let tip = controller.tip, let anchor = anchors[tip.id] {
                let bounds = geometry[anchor]
                let rail = tip.placement == .rail
                let windowSize = geometry.size
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 12) {
                        Text(tip.title).font(.system(size: 13, weight: .medium))
                        if let shortcut = tip.shortcut {
                            Text(shortcut).font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(ReviewTheme.muted)
                                .padding(.horizontal, 4).padding(.vertical, 2)
                                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 4))
                        }
                    }
                    if let hint = tip.hint {
                        Text(hint).font(.system(size: 12)).foregroundStyle(ReviewTheme.muted)
                    }
                }
                .foregroundStyle(ReviewTheme.text)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .frame(maxWidth: 240, alignment: .leading)
                .fixedSize()
                .background(ReviewTheme.raised, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.white.opacity(0.12)))
                .shadow(color: .black.opacity(0.3), radius: 8, y: 3)
                .visualEffect { content, proxy in
                    let size = proxy.size
                    let x = rail ? bounds.maxX + 19 : bounds.maxX - size.width
                    let below = bounds.maxY + 8
                    let y: CGFloat
                    if rail {
                        y = bounds.midY - size.height / 2
                    } else if below + size.height + 8 <= windowSize.height {
                        y = below
                    } else {
                        y = bounds.minY - size.height - 8
                    }
                    return content.offset(
                        x: max(8, min(x, windowSize.width - size.width - 8)),
                        y: max(8, min(y, windowSize.height - size.height - 8))
                    )
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct ReviewIconButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var tint: Color = ReviewTheme.text
    var primary = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(isEnabled ? tint : ReviewTheme.subtle)
            .frame(width: 32, height: 32)
            .background(isEnabled ? (primary ? tint.opacity(configuration.isPressed ? 0.24 : 0.15)
                                             : .white.opacity(configuration.isPressed ? 0.10 : 0.04)) : .clear,
                        in: RoundedRectangle(cornerRadius: ReviewTheme.navigationRadius))
            .overlay {
                RoundedRectangle(cornerRadius: ReviewTheme.navigationRadius)
                    .strokeBorder(isEnabled ? (primary ? tint.opacity(0.2) : ReviewTheme.line) : .white.opacity(0.05))
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
    }
}
