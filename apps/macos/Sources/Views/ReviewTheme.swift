import AppKit
import SwiftUI

enum ReviewTheme {
    static let detailWidth: CGFloat = 700
    static let background = Color(red: 0.043, green: 0.047, blue: 0.055)
    static let workspace = Color(red: 0.082, green: 0.086, blue: 0.098)
    static let panel = Color(red: 0.110, green: 0.114, blue: 0.129)
    static let raised = Color(red: 0.145, green: 0.149, blue: 0.165)
    static let text = Color(red: 0.925, green: 0.929, blue: 0.937)
    static let accent = text
    static let muted = Color(red: 0.631, green: 0.643, blue: 0.671)
    static let subtle = Color(red: 0.502, green: 0.514, blue: 0.549)
    static let line = Color.white.opacity(0.10)
    static let navigationRadius: CGFloat = 8
    static let selectionOpacity = 0.10
    static let hoverFill = Color.white.opacity(0.05)
    static let pressedFill = Color.white.opacity(0.065)

    @MainActor static func onAccent(tint: Color) -> Color {
        let fill = NSColor(tint)
        return contrast(.black, against: fill) >= contrast(.white, against: fill) ? .black : .white
    }

    static func contrast(_ foreground: NSColor, against background: NSColor) -> Double {
        let first = luminance(foreground)
        let second = luminance(background)
        return (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }

    private static func luminance(_ color: NSColor) -> Double {
        guard let rgb = color.usingColorSpace(.sRGB) else { return 0 }
        func linear(_ component: CGFloat) -> Double {
            let value = Double(component)
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(rgb.redComponent) + 0.7152 * linear(rgb.greenComponent) + 0.0722 * linear(rgb.blueComponent)
    }

    static func nativeColor(hex: String) -> NSColor? {
        let text = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        return NSColor(
            srgbRed: CGFloat((value >> 16) & 255) / 255,
            green: CGFloat((value >> 8) & 255) / 255,
            blue: CGFloat(value & 255) / 255, alpha: 1
        )
    }
}

extension View {
    func reviewWorkspaceSurface() -> some View {
        let shape = RoundedRectangle(cornerRadius: 11)
        return self
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ReviewTheme.workspace, in: shape)
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(.white.opacity(0.04))
                    .allowsHitTesting(false)
            }
            .padding(8)
    }
}

struct ReviewPrimaryForeground: ViewModifier {
    @Environment(\.controlActiveState) private var activeState
    @Environment(\.isEnabled) private var isEnabled
    let tint: Color

    @ViewBuilder func body(content: Content) -> some View {
        if activeState != .inactive && isEnabled {
            content.foregroundStyle(ReviewTheme.onAccent(tint: tint))
        } else {
            content
        }
    }
}

struct ReviewRowButtonStyle: ButtonStyle {
    let selected: Bool
    let tint: Color
    var cornerRadius: CGFloat = ReviewTheme.navigationRadius

    func makeBody(configuration: Configuration) -> some View {
        ReviewRowButtonLabel(configuration: configuration, selected: selected, tint: tint, cornerRadius: cornerRadius)
    }
}

private struct ReviewRowButtonLabel: View {
    let configuration: ButtonStyleConfiguration
    let selected: Bool
    let tint: Color
    let cornerRadius: CGFloat
    @State private var hovering = false
    @Environment(\.controlActiveState) private var activeState

    var body: some View {
        configuration.label
            .background {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(selected ? tint.opacity(ReviewTheme.selectionOpacity) : .clear)
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(configuration.isPressed ? (selected ? Color.white.opacity(0.025) : ReviewTheme.pressedFill)
                                  : hovering && activeState != .inactive ? (selected ? Color.white.opacity(0.012) : ReviewTheme.hoverFill) : .clear)
                    }
            }
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
            .onHover { hovering = $0 }
            .onDisappear { hovering = false }
            .onChange(of: activeState) { _, state in
                if state == .inactive { hovering = false }
            }
    }
}

struct ReviewTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .textFieldStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(ReviewTheme.panel, in: RoundedRectangle(cornerRadius: ReviewTheme.navigationRadius))
            .overlay(RoundedRectangle(cornerRadius: ReviewTheme.navigationRadius).strokeBorder(ReviewTheme.line).allowsHitTesting(false))
    }
}

struct ReviewCollectionHeader<Actions: View>: View {
    @State private var isBackHovered = false
    let title: String
    let itemTitle: String?
    let goBack: () -> Void
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        HStack(spacing: 10) {
            if let itemTitle {
                Button(action: goBack) {
                    Text(title)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(isBackHovered ? ReviewTheme.text : ReviewTheme.muted)
                        .underline(isBackHovered)
                }
                .buttonStyle(.plain)
                .fixedSize()
                .onHover { isBackHovered = $0 }
                .onDisappear { isBackHovered = false }
                .accessibilityLabel("Back to \(title)")
                .keyboardShortcut("[", modifiers: .command)
                .background {
                    Button("Back to \(title)", action: goBack)
                        .keyboardShortcut(.cancelAction)
                        .hidden()
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(ReviewTheme.subtle)
                    .accessibilityHidden(true)
                Text(itemTitle)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(ReviewTheme.text)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
            } else {
                ReviewPageHeader(title: title, size: 19)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer(minLength: 8)
            actions()
        }
        .frame(maxWidth: ReviewTheme.detailWidth)
        .frame(height: 32)
        .padding(.horizontal, 28)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }
}

struct ReviewCollectionSearchField: View {
    let collection: String
    @Binding var query: String
    let searchFocus: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(ReviewTheme.muted)
            TextField("Search \(collection.lowercased())", text: $query)
                .textFieldStyle(.plain)
                .focused(searchFocus)
                .accessibilityLabel("Search \(collection.lowercased())")
                .onExitCommand { query = "" }
            if !query.isEmpty {
                Button {
                    query = ""
                    searchFocus.wrappedValue = true
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(ReviewTheme.muted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear \(collection.lowercased()) search")
            }
        }
        .font(.system(size: 13))
        .padding(.horizontal, 11)
        .frame(width: 250, height: 32)
        .background(ReviewTheme.panel, in: RoundedRectangle(cornerRadius: ReviewTheme.navigationRadius))
        .overlay(RoundedRectangle(cornerRadius: ReviewTheme.navigationRadius).strokeBorder(ReviewTheme.line).allowsHitTesting(false))
    }
}

struct ReviewPageHeader: View {
    let title: String
    var size: CGFloat = 26

    var body: some View {
        Text(title)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(ReviewTheme.text)
    }
}

struct ReviewCrabView: View {
    let variant: String
    let size: CGFloat
    let customHex: String?

    init(variant: String, size: CGFloat, customHex: String? = nil) {
        self.variant = variant
        self.size = size
        self.customHex = customHex
    }

    var body: some View {
        Group {
            if let image = ReviewSpriteCache.image(variant: variant, customHex: customHex) {
                Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
            } else {
                Image(systemName: "waveform").resizable().scaledToFit()
                    .foregroundStyle(ReviewTheme.muted)
            }
        }
        .frame(width: size, height: size * 0.82)
        .accessibilityLabel("ShoutOut crab")
    }
}

@MainActor private enum ReviewSpriteCache {
    private static let images = NSCache<NSString, NSImage>()

    static func image(variant: String, customHex: String?) -> NSImage? {
        let key = "\(variant):\(customHex ?? "")" as NSString
        if let image = images.object(forKey: key) { return image }
        let safeVariant = customHex == nil ? (CrabColorVariant(rawValue: variant)?.rawValue ?? "ocean") : "ocean"
        guard let url = Bundle.main.resourceURL?
            .appendingPathComponent("CrabSpriteVariants/\(safeVariant)/idle-1.png"),
            var image = NSImage(contentsOf: url)
        else { return nil }

        if let customHex, let color = ReviewTheme.nativeColor(hex: customHex) {
            image = IndicatorSpriteTint.tintedImage(image, color: color) ?? image
        }
        images.setObject(image, forKey: key)
        return image
    }
}
