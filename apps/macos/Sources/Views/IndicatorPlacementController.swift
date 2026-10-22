import AppKit

/// Owns desktop placement and the temporary, nonactivating drag guide windows.
@MainActor
final class IndicatorPlacementController {
    private weak var panel: NSPanel?
    private weak var model: IndicatorOverlayModel?
    private let defaults: UserDefaults
    private let pointerLocation: () -> CGPoint
    private var pointerTimer: Timer?
    private var sampledPointer: CGPoint?
    private var guidePanels: [NSPanel] = []
    private var escapeMonitor: Any?
    private var globalEscapeMonitor: Any?
    private var mouseDownMonitor: Any?
    private var localPointerMonitor: Any?
    private var globalPointerMonitor: Any?
    private var interactionRect = CGRect.zero
    private var screenObserver: NSObjectProtocol?
    private var dragOrigin: CGPoint?
    private var originalFrame = CGRect.zero
    private var originalLevel = NSWindow.Level.statusBar
    private var cancelledUntilRelease = false
    private var pointerStartedOnIndicator = false
    private var hasDragCursor = false
    private var selectedTarget: (screen: NSScreen, anchor: IndicatorAnchor)?
    private(set) var isDragging = false
    private var actionResumeAt = Date.distantPast
    var acceptsActions: Bool { !isDragging && Date() >= actionResumeAt }

    init(defaults: UserDefaults = .standard, pointerLocation: @escaping () -> CGPoint = { NSEvent.mouseLocation }) {
        self.defaults = defaults
        self.pointerLocation = pointerLocation
    }

    func attach(panel: NSPanel, model: IndicatorOverlayModel) {
        tearDown()
        self.panel = panel
        self.model = model
        model.onDragChanged = { [weak self, weak model] location, translation in
            guard let self, self.model === model else { return }
            self.dragIndicator(location: location, translation: translation)
        }
        model.onDragEnded = { [weak self, weak model] in
            guard let self, self.model === model else { return }
            self.finishDrag()
        }
        model.onInteractionRegionChanged = { [weak self, weak model] rect in
            guard let self, self.model === model else { return }
            self.interactionRect = rect
            self.updateMouseRouting()
        }
        observePointerEvents()
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.samplePointer() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pointerTimer = timer
        observeScreenChanges()
    }

    // Click-through windows can miss the mouse-move event that would make them interactive.
    func samplePointer() {
        guard panel?.isVisible == true, !isDragging, !pointerStartedOnIndicator else { return }
        let pointer = pointerLocation()
        guard pointer != sampledPointer else { return }
        sampledPointer = pointer
        updateMouseRouting(at: pointer)
    }

    private func observePointerEvents() {
        localPointerMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            self?.updateMouseRouting(at: screenPoint(for: event))
            return event
        }
        globalPointerMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            Task { @MainActor in
                if event.type == .leftMouseUp { self?.pointerStartedOnIndicator = false }
                self?.updateMouseRouting(at: screenPoint(for: event))
            }
        }
        mouseDownMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { [weak self] event in
            if event.type == .leftMouseDown {
                self?.cancelledUntilRelease = false
                self?.pointerStartedOnIndicator = event.window == self?.panel
            } else {
                self?.pointerStartedOnIndicator = false
                self?.updateMouseRouting()
            }
            return event
        }
    }

    private func observeScreenChanges() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.cancelDrag()
                self.placeIndicator()
            }
        }
    }

    func placeIndicator() {
        guard !isDragging, let panel, let model, let screen = findScreen(for: model.style) else { return }
        let anchor = getAnchor(for: model.style)
        model.anchor = anchor
        model.crabHeight = max(screen.visibleFrame.height / 3, 220)
        panel.setFrame(anchor.frame(in: screen.visibleFrame, style: model.style, crabHeight: model.crabHeight), display: true)
        updateMouseRouting()
    }

    private func updateMouseRouting(at screenPoint: CGPoint? = nil) {
        guard let panel, let view = panel.contentView else { return }
        let point = view.convert(panel.convertPoint(fromScreen: screenPoint ?? pointerLocation()), from: nil)
        let hitRect = getIndicatorHitFrame(for: interactionRect, style: model?.style ?? .off,
                                               anchor: model?.anchor ?? .right, in: view.bounds)
        (view as? IndicatorHostingView)?.dragRect = hitRect
        if model?.dragRect != hitRect { model?.dragRect = hitRect }
#if DEBUG
        defer { writeDebugSnapshot(pointer: point, panel: panel) }
#endif
        guard !isDragging && !pointerStartedOnIndicator else { panel.ignoresMouseEvents = false; return }
        let radius = model?.style == .crab ? 0 : min(hitRect.width, hitRect.height) / 2
        let isHovered = CGPath(roundedRect: hitRect, cornerWidth: radius, cornerHeight: radius, transform: nil).contains(point)
        panel.ignoresMouseEvents = !isHovered
        if model?.isHovered != isHovered { model?.isHovered = isHovered }
    }

    func cancelDrag() {
        guard isDragging else { return }
        cancelledUntilRelease = true
        endDrag()
        placeIndicator()
    }

    func tearDown() {
        pointerTimer?.invalidate()
        pointerTimer = nil
        cancelDrag()
        hideGuides()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        if let mouseDownMonitor { NSEvent.removeMonitor(mouseDownMonitor) }
        mouseDownMonitor = nil
        if let localPointerMonitor { NSEvent.removeMonitor(localPointerMonitor) }
        if let globalPointerMonitor { NSEvent.removeMonitor(globalPointerMonitor) }
        localPointerMonitor = nil
        globalPointerMonitor = nil
        model?.onDragChanged = nil
        model?.onDragEnded = nil
        model?.onInteractionRegionChanged = nil
        model?.isHovered = false
        model?.dragRect = .zero
        interactionRect = .zero
        sampledPointer = nil
        pointerStartedOnIndicator = false
        cancelledUntilRelease = false
        panel = nil
        model = nil
    }

    private func getAnchor(for style: OverlayStyle) -> IndicatorAnchor {
        guard let raw = defaults.string(forKey: "indicatorAnchor.\(style.rawValue)"),
              let anchor = IndicatorAnchor(rawValue: raw),
              IndicatorAnchor.allowed(for: style).contains(anchor) else { return .right }
        return anchor
    }

    private func findScreen(for style: OverlayStyle) -> NSScreen? {
        let identifier = defaults.object(forKey: "indicatorDisplay.\(style.rawValue)") as? NSNumber
        return NSScreen.screens.first { identifier != nil && $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber == identifier }
            ?? NSScreen.main ?? NSScreen.screens.first
    }

    private func dragIndicator(location: CGPoint, translation: CGSize) {
        guard !cancelledUntilRelease, let panel, let model, model.style != .off else { return }
        let windowPoint = panel.contentView?.convert(location, to: nil) ?? location
        let pointer = panel.convertPoint(toScreen: windowPoint)
        if !isDragging {
            isDragging = true
            model.isDragging = true
            panel.disableCursorRects()
            NSCursor.closedHand.push()
            hasDragCursor = true
            panel.ignoresMouseEvents = false
            originalFrame = panel.frame
            originalLevel = panel.level
            dragOrigin = CGPoint(x: pointer.x - translation.width, y: pointer.y + translation.height)
            showGuides(style: model.style)
            panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 2)
            panel.orderFrontRegardless()
            escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard event.keyCode == 53 else { return event }
                self?.cancelDrag()
                return nil
            }
            globalEscapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard event.keyCode == 53 else { return }
                Task { @MainActor in self?.cancelDrag() }
            }
        }
        guard let dragOrigin else { return }
        panel.setFrameOrigin(CGPoint(x: originalFrame.minX + pointer.x - dragOrigin.x,
                                     y: originalFrame.minY + pointer.y - dragOrigin.y))
        selectedTarget = NSScreen.screens.compactMap { screen in
            guard screen.frame.contains(pointer) else { return nil as (screen: NSScreen, anchor: IndicatorAnchor)? }
            return IndicatorAnchor.dropTarget(at: pointer, in: screen.visibleFrame, style: model.style)
                .map { (screen: screen, anchor: $0) }
        }.first
        for guide in guidePanels {
            guard let view = guide.contentView as? IndicatorDropGuideView else { continue }
            view.selectedAnchor = selectedTarget?.screen == view.screen ? selectedTarget?.anchor : nil
        }
    }

    private func finishDrag() {
        defer { cancelledUntilRelease = false }
        guard isDragging, let model else { return }
        if let selectedTarget {
            defaults.set(selectedTarget.anchor.rawValue, forKey: "indicatorAnchor.\(model.style.rawValue)")
            defaults.set(selectedTarget.screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")],
                         forKey: "indicatorDisplay.\(model.style.rawValue)")
            if model.style == .crab { model.crabPlacementRevision += 1 }
        }
        endDrag()
        placeIndicator()
    }

    private func endDrag() {
        actionResumeAt = Date().addingTimeInterval(0.2)
        isDragging = false
        model?.isDragging = false
        if hasDragCursor {
            NSCursor.pop()
            panel?.enableCursorRects()
            hasDragCursor = false
        }
        dragOrigin = nil
        selectedTarget = nil
        hideGuides()
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        escapeMonitor = nil
        if let globalEscapeMonitor { NSEvent.removeMonitor(globalEscapeMonitor) }
        globalEscapeMonitor = nil
        panel?.level = originalLevel
    }

    private func showGuides(style: OverlayStyle) {
        hideGuides()
        for screen in NSScreen.screens {
            let guide = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
            guide.isOpaque = false
            guide.backgroundColor = .clear
            guide.hasShadow = false
            guide.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
            guide.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
            guide.hidesOnDeactivate = false
            guide.ignoresMouseEvents = true
            guide.isReleasedWhenClosed = false
            guide.title = "ShoutOut placement targets"
            guide.contentView = IndicatorDropGuideView(screen: screen, style: style)
            guide.orderFrontRegardless()
            guidePanels.append(guide)
        }
    }

    private func hideGuides() {
        for guide in guidePanels { guide.orderOut(nil) }
        guidePanels.removeAll()
    }

#if DEBUG
    private func writeDebugSnapshot(pointer: CGPoint, panel: NSPanel) {
        guard let path = ProcessInfo.processInfo.environment["SHOUTOUT_INDICATOR_DEBUG_PATH"] else { return }
        let snapshot: [String: Any] = [
            "frame": NSStringFromRect(panel.frame), "interaction": NSStringFromRect(interactionRect),
            "pointer": NSStringFromPoint(pointer), "ignoresMouse": panel.ignoresMouseEvents,
            "bounds": NSStringFromRect(panel.contentView?.bounds ?? .zero),
            "hitFrame": NSStringFromRect(model?.dragRect ?? .zero), "hovered": model?.isHovered ?? false,
            "anchor": model?.anchor.rawValue ?? "", "style": model?.style.rawValue ?? "",
            "window": panel.windowNumber, "isDragging": isDragging, "pressed": pointerStartedOnIndicator,
            "guideCount": guidePanels.filter(\.isVisible).count, "target": selectedTarget?.anchor.rawValue ?? "",
        ]
        if let data = try? JSONSerialization.data(withJSONObject: snapshot, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
        }
    }

    func previewPlacement(anchor: IndicatorAnchor, showsGuides: Bool) {
        guard !isDragging, let model else { return }
        defaults.set(anchor.rawValue, forKey: "indicatorAnchor.\(model.style.rawValue)")
        placeIndicator()
        if showsGuides {
            showGuides(style: model.style)
            panel?.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 2)
        } else {
            hideGuides()
            panel?.level = .statusBar
        }
    }
#endif
}

private final class IndicatorDropGuideView: NSView {
    let screen: NSScreen
    let style: OverlayStyle
    var selectedAnchor: IndicatorAnchor? { didSet { needsDisplay = true } }

    init(screen: NSScreen, style: OverlayStyle) {
        self.screen = screen
        self.style = style
        super.init(frame: CGRect(origin: .zero, size: screen.frame.size))
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.38).setFill()
        bounds.fill()
        for anchor in IndicatorAnchor.allowed(for: style) {
            let target = anchor.targetFrame(in: screen.visibleFrame)
                .offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)
            let selected = anchor == selectedAnchor
            let path = NSBezierPath(roundedRect: target, xRadius: 44, yRadius: 44)
            NSColor.white.withAlphaComponent(selected ? 0.75 : 0.20).setFill()
            path.fill()
            NSColor.white.withAlphaComponent(selected ? 0.95 : 0.42).setStroke()
            path.lineWidth = selected ? 2 : 1
            path.stroke()
        }
    }
}

@MainActor
private func screenPoint(for event: NSEvent) -> CGPoint {
    event.window?.convertPoint(toScreen: event.locationInWindow) ?? event.locationInWindow
}
