import SwiftUI
import ShoutOutCore

enum ShoutOutHomeSection: String, CaseIterable, Identifiable {
    case insights
    case dictionary
    case history
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .insights: return "Insights"
        case .dictionary: return "Dictionary"
        case .history: return "History"
        case .settings: return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .insights: return "chart.bar"
        case .dictionary: return "character.book.closed"
        case .history: return "clock.arrow.circlepath"
        case .settings: return "slider.horizontal.3"
        }
    }
}

@MainActor
final class ShoutOutHomeWindowModel: ObservableObject {
    @Published var selectedSection: ShoutOutHomeSection = .history
}

struct ShoutOutHomeView: View {
    static let minimumSize = CGSize(width: 860, height: 600)

    @State private var tooltips = ReviewTooltipController()
    @ObservedObject var model: ShoutOutHomeWindowModel
    let getUsageStats: @MainActor () -> UsageStatsStore
    let getDictionary: @MainActor () -> DictionaryStore
    @State private var insightsRange = UsageInsightsRange.month
    @State private var historyQuery = ""
    @State private var selectedHistoryID: UUID?
    @State private var historyListPosition: UUID?
    @State private var dictionaryQuery = ""
    @State private var selectedDictionaryID: UUID?
    @State private var dictionaryListPosition: UUID?
    @State private var dictionaryTestText = ""
    @State private var selectedSettingsPane: ReviewSettingsView.Pane = .dictation
    @AppStorage(Defaults.crabColorVariant) private var variant = CrabColorVariant.ocean.rawValue
    @AppStorage(Defaults.customIndicatorTint) private var customTint = "#8C7AF5"
    @AppStorage(Defaults.usesCustomIndicatorTint) private var usesCustomTint = false

    private let tint = ReviewTheme.accent

    private var selectedSection: ShoutOutHomeSection {
        model.selectedSection
    }

    var body: some View {
        HStack(spacing: 0) {
            iconRail
            Group {
                switch selectedSection {
                case .history:
                    ReviewHistoryView(
                        tint: tint, variant: variant, customHex: usesCustomTint ? customTint : nil,
                        query: $historyQuery, selectedID: $selectedHistoryID, listPosition: $historyListPosition
                    )
                case .dictionary:
                    ReviewDictionaryView(
                        tint: tint,
                        query: $dictionaryQuery,
                        selectedEntryID: $selectedDictionaryID,
                        listPosition: $dictionaryListPosition,
                        testText: $dictionaryTestText
                    )
                    .environmentObject(getDictionary())
                case .insights:
                    ReviewInsightsView(range: $insightsRange, tint: tint)
                        .environmentObject(getUsageStats())
                case .settings:
                    ReviewSettingsView(tint: tint, selectedPane: $selectedSettingsPane, getUsageStats: getUsageStats)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .overlayPreferenceValue(ReviewTooltipAnchors.self) { anchors in
            ReviewTooltipOverlay(controller: tooltips, anchors: anchors)
        }
        .environmentObject(tooltips)
        .onAppear { tooltips.startMonitoring() }
        .onDisappear { tooltips.stopMonitoring() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in tooltips.dismiss() }
        .frame(minWidth: Self.minimumSize.width, minHeight: Self.minimumSize.height)
        .background(ReviewTheme.background)
        .foregroundStyle(ReviewTheme.text)
        .tint(tint)
        .toggleStyle(.switch)
        .preferredColorScheme(.dark)
        .onChange(of: model.selectedSection) { tooltips.dismiss() }
    }

    private var iconRail: some View {
        VStack(spacing: 11) {
            ReviewTooltippedButton(title: "ShoutOut · History", shortcut: "⌘1", placement: .rail) {
                model.selectedSection = .history
            } label: {
                ReviewCrabView(variant: variant, size: 38, customHex: usesCustomTint ? customTint : nil)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(ReviewRailButtonStyle())
            .accessibilityLabel("ShoutOut, go to History")
            .onHover { inside in
                if inside { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
            }
            .padding(.top, 13)
            .padding(.bottom, 8)

            navigationButton(.history, key: "1")
            navigationButton(.dictionary, key: "2")
            navigationButton(.insights, key: "3")
            navigationButton(.settings, key: "4")
            Spacer(minLength: 16)
        }
        .frame(width: 66)
        .frame(maxHeight: .infinity)
        .animation(nil, value: selectedSection)
    }

    private func navigationButton(_ section: ShoutOutHomeSection, key: String) -> some View {
        ReviewTooltippedButton(title: section.title, shortcut: "⌘\(key)", placement: .rail) {
            if selectedSection == section {
                if section == .history { selectedHistoryID = nil }
                if section == .dictionary { selectedDictionaryID = nil }
                return
            }
            model.selectedSection = section
        } label: {
            Image(systemName: section == .settings ? "gearshape" : section == .dictionary ? "book.closed" : section.systemImage)
                .font(.system(size: 18, weight: .medium))
                .symbolRenderingMode(.monochrome)
                .frame(width: 44, height: 44)
                .foregroundStyle(selectedSection == section ? ReviewTheme.text : ReviewTheme.muted)
                .background {
                    if selectedSection == section {
                        RoundedRectangle(cornerRadius: ReviewTheme.navigationRadius)
                            .fill(tint.opacity(ReviewTheme.selectionOpacity))
                            .overlay(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 2).fill(tint)
                                    .frame(width: 3, height: 25)
                            }
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(ReviewRailButtonStyle())
        .accessibilityLabel(section.title)
        .accessibilityAddTraits(selectedSection == section ? .isSelected : [])
        .keyboardShortcut(KeyEquivalent(Character(key)), modifiers: .command)
    }
}

private struct ReviewRailButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? ReviewTheme.pressedFill : .clear,
                        in: RoundedRectangle(cornerRadius: ReviewTheme.navigationRadius))
    }
}
