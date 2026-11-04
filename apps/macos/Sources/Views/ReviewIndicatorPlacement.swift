import AppKit
import SwiftUI

struct ReviewIndicatorPlacement: View {
    let style: OverlayStyle
    let customHex: String?
    let tint: Color
    let onStyleChanged: (OverlayStyle) -> Void
    let onPlacementChanged: () -> Void

    @AppStorage private var savedAnchor: IndicatorAnchor
    @AppStorage private var savedDisplayID: Int?
    @State private var displays: [DisplayOption] = []
    @State private var contentHeight: CGFloat = 0

    private struct DisplayOption: Identifiable {
        let id: Int
        let name: String
        let isMain: Bool
    }

    init(
        style: OverlayStyle,
        customHex: String?,
        tint: Color,
        onStyleChanged: @escaping (OverlayStyle) -> Void,
        onPlacementChanged: @escaping () -> Void
    ) {
        self.style = style
        self.customHex = customHex
        self.tint = tint
        self.onStyleChanged = onStyleChanged
        self.onPlacementChanged = onPlacementChanged
        _savedAnchor = AppStorage(wrappedValue: .right, "indicatorAnchor.\(style.rawValue)")
        _savedDisplayID = AppStorage("indicatorDisplay.\(style.rawValue)")
    }

    private var allowedAnchors: [IndicatorAnchor] { IndicatorAnchor.allowed(for: style) }

    private var visibleAnchor: IndicatorAnchor {
        allowedAnchors.contains(savedAnchor) ? savedAnchor : .right
    }

    private var visibleDisplayID: Int {
        if let savedDisplayID, displays.contains(where: { $0.id == savedDisplayID }) {
            return savedDisplayID
        }
        return displays.first(where: \.isMain)?.id ?? displays.first?.id ?? 0
    }

    private var savedDisplayIsDisconnected: Bool {
        guard let savedDisplayID else { return false }
        return !displays.contains { $0.id == savedDisplayID }
    }

    var body: some View {
        GeometryReader { geometry in
            placementContent(width: geometry.size.width)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: geometry.size.width, alignment: .leading)
                .onGeometryChange(for: CGFloat.self) { proxy in proxy.size.height } action: {
                    contentHeight = $0
                }
        }
        .frame(height: contentHeight)
        .onAppear { refreshDisplays() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            refreshDisplays()
        }
    }

    @ViewBuilder
    private func placementContent(width: CGFloat) -> some View {
        if width >= 640 {
            HStack(alignment: .top, spacing: 20) {
                preview.frame(width: (width - 20) / 2)
                placementRows.frame(width: (width - 20) / 2)
            }
        } else {
            VStack(alignment: .leading, spacing: 14) {
                preview
                placementRows
            }
        }
    }

    private var preview: some View {
        ReviewIndicatorPreview(
            style: style,
            anchor: visibleAnchor,
            customHex: customHex
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var placementRows: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Style")
                    .font(.system(size: 15, weight: .medium))
                Picker("Indicator style", selection: Binding(
                    get: { style.rawValue },
                    set: { rawStyle in
                        guard let selectedStyle = OverlayStyle(rawValue: rawStyle), selectedStyle != .off else { return }
                        onStyleChanged(selectedStyle)
                    }
                )) {
                    Text("Glass").tag(OverlayStyle.glass.rawValue)
                    Text("Classic").tag(OverlayStyle.capsule.rawValue)
                    Text("Crab").tag(OverlayStyle.crab.rawValue)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Position")
                    .font(.system(size: 15, weight: .medium))
                Picker("Indicator position", selection: Binding(
                    get: { visibleAnchor.rawValue },
                    set: { rawAnchor in
                        guard let anchor = IndicatorAnchor(rawValue: rawAnchor),
                            allowedAnchors.contains(anchor) else { return }
                        savedAnchor = anchor
                        onPlacementChanged()
                    }
                )) {
                    ForEach([IndicatorAnchor.left, .right, .top, .bottom].filter { allowedAnchors.contains($0) }, id: \.rawValue) { anchor in
                        Text(anchor.rawValue.capitalized).tag(anchor.rawValue)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("Indicator position")
            }

            if displays.count > 1 {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Display")
                        .font(.system(size: 15, weight: .medium))
                    Picker("Display", selection: Binding(
                        get: { visibleDisplayID },
                        set: { displayID in
                            guard displays.contains(where: { $0.id == displayID }) else { return }
                            savedDisplayID = displayID
                            onPlacementChanged()
                        }
                    )) {
                        ForEach(displays) { display in
                            Text(display.name + (display.isMain ? " (Main)" : ""))
                                .tag(display.id)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if savedDisplayIsDisconnected {
                Text("Saved display isn’t connected.")
                    .font(.system(size: 13))
                    .foregroundStyle(ReviewTheme.muted)
            }
            Text("Saved per style.\nDrag the indicator to move it.")
                .font(.system(size: 13))
                .foregroundStyle(ReviewTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func refreshDisplays() {
        let mainDisplayID = (NSScreen.main?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.intValue
        displays = NSScreen.screens.enumerated().compactMap { index, screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return nil
            }
            return DisplayOption(id: number.intValue, name: screen.localizedName,
                                 isMain: mainDisplayID.map { $0 == number.intValue } ?? (index == 0))
        }
    }
}
