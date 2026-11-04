import AppKit
import SwiftUI

struct ReviewIndicatorColorPicker: View {
    @Binding var variant: String
    @Binding var customHex: String
    @Binding var usesCustomTint: Bool

    let tint: Color
    let onSelectionChanged: () -> Void

    @State private var showsPalette = false

    private var currentName: String {
        usesCustomTint ? "Custom" : (CrabColorVariant(rawValue: variant) ?? .ocean).displayName
    }

    private var currentColor: Color {
        usesCustomTint
            ? Color(nsColor: ReviewTheme.nativeColor(hex: customHex) ?? NSColor(tint))
            : (CrabColorVariant(rawValue: variant) ?? .ocean).swatchColor
    }

    var body: some View {
        Button {
            showsPalette.toggle()
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(currentColor)
                    .frame(width: 16, height: 16)
                    .overlay(Circle().stroke(ReviewTheme.line, lineWidth: 1))
                Text(currentName)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(ReviewTheme.muted)
            }
            .font(.system(size: 13))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered)
        .tint(ReviewTheme.text)
        .accessibilityLabel("Indicator color: \(currentName)")
        .popover(isPresented: $showsPalette, arrowEdge: .bottom) {
            ReviewIndicatorColorPalette(
                variant: $variant,
                customHex: $customHex,
                usesCustomTint: $usesCustomTint,
                tint: tint,
                showsPalette: $showsPalette,
                onSelectionChanged: onSelectionChanged
            )
        }
    }
}

private struct ReviewIndicatorColorPalette: View {
    @Binding var variant: String
    @Binding var customHex: String
    @Binding var usesCustomTint: Bool
    @Binding var showsPalette: Bool

    let tint: Color
    let onSelectionChanged: () -> Void

    @State private var customDraft: String
    @FocusState private var focusedSwatch: Int?

    private let columns = Array(repeating: GridItem(.fixed(32), spacing: 10), count: 7)

    init(
        variant: Binding<String>,
        customHex: Binding<String>,
        usesCustomTint: Binding<Bool>,
        tint: Color,
        showsPalette: Binding<Bool>,
        onSelectionChanged: @escaping () -> Void
    ) {
        _variant = variant
        _customHex = customHex
        _usesCustomTint = usesCustomTint
        _showsPalette = showsPalette
        self.tint = tint
        self.onSelectionChanged = onSelectionChanged
        _customDraft = State(initialValue: customHex.wrappedValue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Indicator color")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ReviewTheme.text)

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(CrabColorVariant.allCases.indices, id: \.self) { index in
                    let color = CrabColorVariant.allCases[index]
                    Button {
                        select(color)
                    } label: {
                        Circle()
                            .fill(color.swatchColor)
                            .frame(width: 22, height: 22)
                            .overlay(Circle().stroke(.white.opacity(0.18), lineWidth: 1))
                            .overlay {
                                if !usesCustomTint && variant == color.rawValue {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(ReviewTheme.onAccent(tint: color.swatchColor))
                                }
                            }
                            .overlay {
                                if !usesCustomTint && variant == color.rawValue {
                                    Circle()
                                        .stroke(tint, lineWidth: 2)
                                        .frame(width: 28, height: 28)
                                }
                            }
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .focusable(true)
                    .focused($focusedSwatch, equals: index)
                    .overlay {
                        if focusedSwatch == index {
                            RoundedRectangle(cornerRadius: ReviewTheme.navigationRadius)
                                .stroke(ReviewTheme.text, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                                .frame(width: 36, height: 36)
                                .allowsHitTesting(false)
                        }
                    }
                    .help(color.displayName)
                    .accessibilityLabel(color.displayName)
                    .accessibilityAddTraits(!usesCustomTint && variant == color.rawValue ? .isSelected : [])
                    .onKeyPress(.return) {
                        select(color)
                        return .handled
                    }
                    .onKeyPress(.space) {
                        select(color)
                        return .handled
                    }
                    .onExitCommand { showsPalette = false }
                }
            }
            .onMoveCommand(perform: moveFocus)

            Divider()

            Text("Custom color")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ReviewTheme.text)
            HStack(spacing: 10) {
                ColorPicker("Custom color", selection: customColor, supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 32, height: 32)
                    .overlay {
                        if usesCustomTint {
                            ZStack {
                                Circle()
                                    .stroke(tint, lineWidth: 2)
                                    .frame(width: 28, height: 28)
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(ReviewTheme.onAccent(tint: displayedCustomColor))
                            }
                            .allowsHitTesting(false)
                        }
                    }
                    .accessibilityLabel("Custom color")
                    .accessibilityValue(usesCustomTint ? "Custom color active" : "Custom color inactive")
                    .accessibilityAddTraits(usesCustomTint ? .isSelected : [])
                TextField("#8C7AF5", text: $customDraft)
                    .textFieldStyle(ReviewTextFieldStyle())
                    .font(.system(size: 12, design: .monospaced))
                    .accessibilityLabel("Custom hex color")
                    .accessibilityHint("Enter six hex digits, with an optional number sign")
                    .onChange(of: customDraft) { _, _ in saveValidDraft() }
                    .onSubmit {
                        guard let normalizedHex else { return }
                        customDraft = normalizedHex
                        saveValidDraft()
                    }
                    .onExitCommand { showsPalette = false }
            }
            if normalizedHex == nil {
                Text("Enter six hex digits, such as #8C7AF5.")
                    .font(.system(size: 13))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(width: 316)
        .background(ReviewTheme.panel)
        .task {
            await Task.yield()
            focusedSwatch = CrabColorVariant.allCases.firstIndex { $0.rawValue == variant }
        }
        .onExitCommand { showsPalette = false }
    }

    private func select(_ color: CrabColorVariant) {
        variant = color.rawValue
        usesCustomTint = false
        onSelectionChanged()
        showsPalette = false
    }

    private func moveFocus(_ direction: MoveCommandDirection) {
        let current = focusedSwatch ?? CrabColorVariant.allCases.firstIndex { $0.rawValue == variant } ?? 0
        let next: Int
        switch direction {
        case .left: next = current % 7 == 0 ? current + 6 : current - 1
        case .right: next = current % 7 == 6 ? current - 6 : current + 1
        case .up: next = (current + 14) % 21
        case .down: next = (current + 7) % 21
        default: return
        }
        focusedSwatch = next
    }

    private var normalizedHex: String? {
        let trimmed = customDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        guard digits.count == 6, UInt32(digits, radix: 16) != nil else { return nil }
        return "#" + digits.uppercased()
    }

    private func saveValidDraft() {
        guard let normalizedHex, normalizedHex != customHex || !usesCustomTint else { return }
        customHex = normalizedHex
        usesCustomTint = true
        onSelectionChanged()
    }

    private var customColor: Binding<Color> {
        Binding(
            get: { displayedCustomColor },
            set: { color in
                guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return }
                customDraft = String(format: "#%02X%02X%02X",
                    Int((rgb.redComponent * 255).rounded()),
                    Int((rgb.greenComponent * 255).rounded()),
                    Int((rgb.blueComponent * 255).rounded()))
                saveValidDraft()
            }
        )
    }

    private var displayedCustomColor: Color {
        Color(nsColor: ReviewTheme.nativeColor(hex: customHex) ?? NSColor(tint))
    }
}
