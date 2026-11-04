import AppKit
import ShoutOutCore
import SwiftUI

struct ReviewHistoryView: View {
    @EnvironmentObject private var transcriptionHistory: TranscriptionHistoryStore
    @FocusState private var searchFocused: Bool
    @FocusState private var listFocused: Bool
    @State private var lastViewedID: UUID?
    @State private var focusesSearchOnReturn = false
    @State private var keyboardRowID: UUID?
    @State private var isNavigatingWithKeyboard = false
    @Binding var query: String
    @Binding var selectedID: UUID?
    @Binding var listPosition: UUID?
    @State private var copyFeedbackRevision = 0
    @State private var copiedID: UUID?
    @State private var copyFeedbackTask: Task<Void, Never>?

    let tint: Color
    let variant: String
    let customHex: String?

    init(tint: Color, variant: String, customHex: String?, query: Binding<String>, selectedID: Binding<UUID?>, listPosition: Binding<UUID?>) {
        self.tint = tint
        self.variant = variant
        self.customHex = customHex
        _query = query
        _selectedID = selectedID
        _listPosition = listPosition
    }

    var body: some View {
        let entries = visibleEntries
        let selectedIndex = entries.firstIndex { $0.id == selectedID }
        return VStack(spacing: 0) {
            historyHeader(entries, selectedIndex: selectedIndex)
            if let selectedIndex {
                transcriptDetail(entries[selectedIndex])
            } else {
                historyList(entries)
            }
        }
        .reviewWorkspaceSurface()
        .onDisappear { resetCopyFeedback() }
        .onChange(of: selectedID, initial: true) {
            if let selectedID { lastViewedID = selectedID }
            resetCopyFeedback()
        }
        .onChange(of: query) {
            keyboardRowID = nil
            isNavigatingWithKeyboard = false
            listPosition = nil
        }
        .background {
            Button("Find in history") {
                if selectedIndex == nil {
                    searchFocused = true
                } else {
                    focusesSearchOnReturn = true
                    selectedID = nil
                }
            }
            .keyboardShortcut("f", modifiers: .command)
            .hidden()
        }
    }

    private func historyHeader(_ entries: [TranscriptionHistoryEntry], selectedIndex: Int?) -> some View {
        let preview = selectedIndex.map { index in
            entries[index].text.prefix(120).split(whereSeparator: \.isWhitespace).joined(separator: " ")
        }
        return ReviewCollectionHeader(title: "History", itemTitle: preview, goBack: { selectedID = nil }) {
            if let selectedIndex {
                HStack(spacing: 4) {
                    transcriptNavigationButton(entries, destination: selectedIndex - 1, newer: true)
                    transcriptNavigationButton(entries, destination: selectedIndex + 1, newer: false)
                }
                copyButton(for: entries[selectedIndex])
            } else {
                ReviewCollectionSearchField(collection: "History", query: $query, searchFocus: $searchFocused)
            }
        }
    }

    @ViewBuilder
    private func historyList(_ entries: [TranscriptionHistoryEntry]) -> some View {
        if entries.isEmpty {
            emptyState
                .task { restoreSearchFocus() }
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(dayGroups(for: entries)) { group in
                            Text(group.title)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(ReviewTheme.muted)
                                .padding(.horizontal, 12)
                                .padding(.top, 16)
                                .padding(.bottom, 8)
                                .accessibilityAddTraits(.isHeader)

                            ForEach(group.entries) { entry in
                                historyRow(entry)
                                    .id(entry.id)
                            }
                        }
                    }
                    .scrollTargetLayout()
                    .frame(maxWidth: ReviewTheme.detailWidth, alignment: .leading)
                    .padding(.horizontal, 28)
                    .padding(.bottom, 28)
                    .frame(maxWidth: .infinity)
                }
                .scrollPosition(id: $listPosition, anchor: .top)
                .focusable()
                .focusEffectDisabled()
                .focused($listFocused)
                .onMoveCommand { direction in
                    guard direction == .up || direction == .down else { return }
                    let current = entries.firstIndex { $0.id == keyboardRowID }
                    let step = direction == .down ? 1 : -1
                    let next = current.map { min(max($0 + step, 0), entries.count - 1) } ?? 0
                    let id = entries[next].id
                    keyboardRowID = id
                    isNavigatingWithKeyboard = true
                    proxy.scrollTo(id)
                }
                .onKeyPress(.return) {
                    guard listFocused, let id = keyboardRowID ?? entries.first?.id else { return .ignored }
                    keyboardRowID = id
                    isNavigatingWithKeyboard = true
                    selectedID = id
                    return .handled
                }
                .task {
                    defer { lastViewedID = nil }
                    if focusesSearchOnReturn {
                        restoreSearchFocus()
                    } else if let id = lastViewedID, entries.contains(where: { $0.id == id }) {
                        keyboardRowID = id
                        listFocused = true
                        proxy.scrollTo(id)
                    }
                }
            }
        }
    }

    private func historyRow(_ entry: TranscriptionHistoryEntry) -> some View {
        let showsKeyboardFocus = listFocused && isNavigatingWithKeyboard && keyboardRowID == entry.id
        return Button {
            keyboardRowID = entry.id
            isNavigatingWithKeyboard = false
            selectedID = entry.id
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(entry.text)
                        .font(.system(size: 14))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text("\(entry.date.formatted(date: .omitted, time: .shortened)) · \(transcriptMetadata(entry))")
                        .font(.system(size: 13))
                        .monospacedDigit()
                        .foregroundStyle(ReviewTheme.muted)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ReviewTheme.muted)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .buttonStyle(ReviewRowButtonStyle(selected: false, tint: tint, cornerRadius: ReviewTheme.navigationRadius))
        .overlay {
            RoundedRectangle(cornerRadius: ReviewTheme.navigationRadius)
                .strokeBorder(showsKeyboardFocus ? tint : .clear)
                .allowsHitTesting(false)
        }
        .accessibilityLabel("\(entry.text), \(entry.date.formatted(date: .abbreviated, time: .shortened))")
    }

    private func transcriptDetail(_ entry: TranscriptionHistoryEntry) -> some View {
        ScrollView {
            ReviewTranscriptCard(entry: entry, metadata: transcriptMetadata(entry))
                .equatable()
                .frame(maxWidth: ReviewTheme.detailWidth, alignment: .leading)
                .padding(.horizontal, 28)
                .padding(.top, 16)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity)
        }
        .id(entry.id)
        .onExitCommand {
            isNavigatingWithKeyboard = true
            selectedID = nil
        }
    }

    private func transcriptNavigationButton(_ entries: [TranscriptionHistoryEntry], destination: Int, newer: Bool) -> some View {
        ReviewTooltippedButton(title: newer ? "Newer transcript" : "Older transcript",
                              shortcut: newer ? "⌥↑" : "⌥↓") {
            guard entries.indices.contains(destination) else { return }
            selectedID = entries[destination].id
        } label: {
            Image(systemName: newer ? "chevron.up" : "chevron.down")
        }
        .buttonStyle(ReviewIconButtonStyle())
        .keyboardShortcut(newer ? .upArrow : .downArrow, modifiers: .option)
        .disabled(!entries.indices.contains(destination))
    }

    private func transcriptMetadata(_ entry: TranscriptionHistoryEntry) -> String {
        "\(durationLabel(entry.duration)) · \(entry.wordCount) \(entry.wordCount == 1 ? "word" : "words")"
    }

    private func restoreSearchFocus() {
        guard focusesSearchOnReturn else { return }
        focusesSearchOnReturn = false
        DispatchQueue.main.async { searchFocused = true }
    }

    private func resetCopyFeedback() {
        copyFeedbackTask?.cancel()
        copyFeedbackTask = nil
        copiedID = nil
    }

    private var emptyState: some View {
        let isEmpty = transcriptionHistory.entries.isEmpty
        return VStack(alignment: .leading, spacing: 10) {
            if isEmpty {
                ReviewCrabView(variant: variant, size: 72, customHex: customHex)
            }
            Text(isEmpty ? "Your history is empty" : "No matching transcriptions")
                .font(.system(size: 23, weight: .semibold))
            Text(isEmpty ? "Dictate something to see it here." : "Try another word or clear the search.")
                .font(.system(size: 13))
                .foregroundStyle(ReviewTheme.muted)
            if !isEmpty {
                Button("Clear search") { query = ""; searchFocused = true }
                    .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func copyButton(for entry: TranscriptionHistoryEntry) -> some View {
        ReviewTooltippedButton(
            title: "Copy final text",
            hint: "Removed words aren't included.",
            successMessage: "Copied",
            feedbackRevision: copyFeedbackRevision
        ) {
            copy(entry)
        } label: {
            Image(systemName: copiedID == entry.id ? "checkmark" : "doc.on.doc")
        }
        .buttonStyle(ReviewIconButtonStyle(tint: tint, primary: true))
    }

    private func copy(_ entry: TranscriptionHistoryEntry) {
        NSPasteboard.general.clearContents()
        guard NSPasteboard.general.setString(entry.text, forType: .string) else { return }
        copyFeedbackTask?.cancel()
        copiedID = entry.id
        copyFeedbackRevision += 1
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: "Copied final text", .priority: NSAccessibilityPriorityLevel.medium.rawValue])
        copyFeedbackTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            copiedID = nil
        }
    }

    private var visibleEntries: [TranscriptionHistoryEntry] {
        let entries = transcriptionHistory.recentEntries
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !search.isEmpty else { return entries }
        return (try? TranscriptionHistorySearch.search(entries, query: search)) ?? []
    }

    private func dayGroups(for entries: [TranscriptionHistoryEntry]) -> [HistoryDayGroup] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: entries) { calendar.startOfDay(for: $0.date) }
        return grouped.keys.sorted(by: >).map { day in
                HistoryDayGroup(
                    day: day,
                    title: calendar.isDateInToday(day) ? "Today"
                        : calendar.isDateInYesterday(day) ? "Yesterday"
                        : day.formatted(.dateTime.month(.wide).day().year()),
                    entries: grouped[day] ?? []
                )
            }
    }

    private func durationLabel(_ duration: TimeInterval) -> String {
        let seconds = max(0, Int(duration.rounded()))
        if seconds == 0 { return "<1 sec" }
        if seconds < 60 { return "\(seconds) sec" }
        return "\(seconds / 60)m \(seconds % 60)s"
    }


}

private struct HistoryDayGroup: Identifiable {
    let day: Date
    let title: String
    let entries: [TranscriptionHistoryEntry]

    var id: Date { day }
}

private struct ReviewTranscriptCard: View, Equatable {
    let entry: TranscriptionHistoryEntry
    let metadata: String

    var body: some View {
        let changes = TranscriptTextDiff.segments(from: entry.languagePassInput ?? entry.text, to: entry.text)
        let removedCount = changes.filter { $0.kind == .removed }.count
        let addedCount = changes.filter { $0.kind == .added }.count
        let counts = [
            removedCount > 0 ? "\(removedCount) removed" : nil,
            addedCount > 0 ? "\(addedCount) added" : nil,
        ].compactMap { $0 }

        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(counts.isEmpty ? "No changes" : (["Cleanup"] + counts).joined(separator: " · "))
                    .fontWeight(.medium)
                    .help("Counts changed text spans, including punctuation and spaces.")
                Spacer(minLength: 0)
                Text("\(entry.date.formatted(date: .abbreviated, time: .shortened)) · \(metadata)")
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
            }
            .font(.system(size: 12))
            .foregroundStyle(ReviewTheme.muted)

            Text(diffText(for: changes))
                .font(.system(size: 17))
                .lineSpacing(4)
                .textSelection(.enabled)
                .accessibilityHint("Removed text is struck through. Added text is underlined and highlighted.")
                .frame(maxWidth: 640, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(ReviewTheme.panel, in: RoundedRectangle(cornerRadius: 10))
    }

    private func diffText(for segments: [TranscriptTextDiff.Segment]) -> AttributedString {
        let removedColor = Color(red: 1, green: 0.48, blue: 0.52).opacity(0.75)
        let addedColor = Color(red: 0.52, green: 0.9, blue: 0.65)
        var result = AttributedString()
        for (index, segment) in segments.enumerated() {
            if index > 0, segments[index - 1].kind == .removed, segment.kind == .added,
               let last = segments[index - 1].text.last, let first = segment.text.first,
               !last.isWhitespace && !first.isWhitespace {
                result += AttributedString("\u{2002}")
            }

            let text = segment.text
            var styledRange = text.startIndex..<text.endIndex
            if segment.kind != .unchanged,
               let first = text.firstIndex(where: { !$0.isWhitespace }),
               let last = text.lastIndex(where: { !$0.isWhitespace }) {
                styledRange = first..<text.index(after: last)
            }
            if styledRange.lowerBound != text.startIndex {
                result += AttributedString(String(text[..<styledRange.lowerBound]))
            }
            var part = AttributedString(String(text[styledRange]))
            switch segment.kind {
            case .unchanged:
                part.foregroundColor = ReviewTheme.text
            case .removed:
                part.foregroundColor = removedColor
                part.strikethroughStyle = .single
            case .added:
                part.foregroundColor = addedColor
                part.backgroundColor = addedColor.opacity(0.14)
                part.underlineStyle = .single
            }
            result += part
            if styledRange.upperBound != text.endIndex {
                result += AttributedString(String(text[styledRange.upperBound...]))
            }
        }
        return result
    }
}
