import AppKit
import SwiftUI

extension View {
    func squarePopover<Content: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        background(SquarePopoverAnchor(isPresented: isPresented, content: content()))
    }
}

private struct SquarePopoverAnchor<Content: View>: NSViewRepresentable {
    @Binding var isPresented: Bool
    let content: Content

    func makeNSView(context: Context) -> NSView { NSView() }
    func makeCoordinator() -> Coordinator { Coordinator(isPresented: $isPresented) }

    func updateNSView(_ anchor: NSView, context: Context) {
        context.coordinator.isPresented = $isPresented
        if isPresented {
            context.coordinator.show(content: content, anchoredTo: anchor)
        } else {
            context.coordinator.close()
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.close()
    }

    @MainActor
    final class Coordinator {
        var isPresented: Binding<Bool>
        private var panel: SquareMenuPanel?
        private var hostingView: NSHostingView<AnyView>?
        private var eventMonitor: Any?
        private var observers: [NSObjectProtocol] = []

        init(isPresented: Binding<Bool>) {
            self.isPresented = isPresented
        }

        func show(content: Content, anchoredTo anchor: NSView) {
            guard let parent = anchor.window, let screen = parent.screen else { return }
            let root = AnyView(content.environment(\.colorScheme, .light))
            if let hostingView {
                hostingView.rootView = root
            } else {
                let panel = SquareMenuPanel(
                    contentRect: .zero,
                    styleMask: [.borderless, .nonactivatingPanel],
                    backing: .buffered,
                    defer: false
                )
                panel.isOpaque = false
                panel.backgroundColor = .clear
                panel.hasShadow = true
                panel.isReleasedWhenClosed = false
                panel.level = .popUpMenu
                panel.animationBehavior = .none
                let hostingView = NSHostingView(rootView: root)
                hostingView.wantsLayer = true
                hostingView.layer?.cornerRadius = 0
                panel.contentView = hostingView
                self.panel = panel
                self.hostingView = hostingView
                parent.addChildWindow(panel, ordered: .above)
                installDismissalHandlers(parent: parent, anchor: anchor)
            }
            guard let panel, let hostingView else { return }
            let size = hostingView.fittingSize
            let button = parent.convertToScreen(anchor.convert(anchor.bounds, to: nil))
            let bounds = screen.visibleFrame.insetBy(dx: 8, dy: 8)
            let x = max(bounds.minX, min(button.maxX - size.width, bounds.maxX - size.width))
            let below = button.minY - size.height - 6
            let y = below >= bounds.minY ? below : min(button.maxY + 6, bounds.maxY - size.height)
            panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
            panel.makeKeyAndOrderFront(nil)
        }

        private func installDismissalHandlers(parent: NSWindow, anchor: NSView) {
            eventMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown, .keyDown, .scrollWheel]
            ) { [weak self, weak anchor] event in
                guard let self else { return event }
                if event.type == .keyDown {
                    if event.keyCode == 53 {
                        self.dismiss()
                        return nil
                    }
                } else if event.window !== self.panel {
                    let clickedTrigger = event.type != .scrollWheel
                        && event.window === anchor?.window
                        && anchor.map { $0.bounds.contains($0.convert(event.locationInWindow, from: nil)) } == true
                    if !clickedTrigger { self.dismiss() }
                }
                return event
            }
            for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification, NSWindow.willCloseNotification] {
                observeDismissal(name, object: parent)
            }
            observeDismissal(NSApplication.didResignActiveNotification, object: NSApp)
        }

        private func observeDismissal(_ name: Notification.Name, object: AnyObject) {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.dismiss() }
            })
        }

        private func dismiss() {
            isPresented.wrappedValue = false
            close()
        }

        func close() {
            if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
            eventMonitor = nil
            observers.forEach(NotificationCenter.default.removeObserver)
            observers.removeAll()
            if let panel { panel.parent?.removeChildWindow(panel) }
            panel?.orderOut(nil)
            panel = nil
            hostingView = nil
        }
    }
}

private final class SquareMenuPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
