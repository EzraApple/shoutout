import AppKit
import ShoutOutCore
import SwiftUI

struct ReviewDictionaryView: View {
    @EnvironmentObject private var store: DictionaryStore

    @Binding var query: String
    @Binding var selectedEntryID: UUID?
    @State private var editor: ReviewDictionaryEditorTarget?
    @State private var entryToDelete: DictionaryEntry?
    @State private var errorMessage: String?
    @Binding var listPosition: UUID?
    @State private var returnFocusID: UUID?
    @State private var focusesSearchOnReturn = false
    @Binding var testText: String
    @FocusState private var searchFocused: Bool
    @FocusState private var focusedRowID: UUID?

    let tint: Color

    init(tint: Color, query: Binding<String>, selectedEntryID: Binding<UUID?>, listPosition: Binding<UUID?>, testText: Binding<String>) {
        self.tint = tint
        _query = query
        _selectedEntryID = selectedEntryID
        _listPosition = listPosition
        _testText = testText
    }

    var body: some View {
        let entry = store.loadError == nil ? selectedEntry : nil
        return VStack(spacing: 0) {
            ReviewCollectionHeader(title: "Dictionary", itemTitle: entry?.phrase, goBack: { selectedEntryID = nil }) {
                if let entry {
                    entryActions(entry)
                } else {
                    ReviewTooltippedButton(title: "Add entry", shortcut: "⌘N") {
                        editor = ReviewDictionaryEditorTarget(entry: nil)
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(ReviewIconButtonStyle())
                    .disabled(store.loadError != nil)
                    ReviewCollectionSearchField(collection: "Dictionary", query: $query, searchFocus: $searchFocused)
                }
            }

            if let entry {
                ScrollView {
                    entryDetail(entry)
                        .frame(maxWidth: ReviewTheme.detailWidth, alignment: .leading)
                        .padding(.horizontal, 28)
                        .padding(.top, 16)
                        .padding(.bottom, 28)
                        .frame(maxWidth: .infinity)
                }
                .id(entry.id)
                .onExitCommand { selectedEntryID = nil }
            } else {
                entryList
            }
        }
        .reviewWorkspaceSurface()
        .foregroundStyle(ReviewTheme.text)
        .tint(tint)
        .sheet(item: $editor) { target in
            ReviewDictionaryEditor(store: store, entry: target.entry, tint: tint) { savedID in
                selectedEntryID = savedID
            }
        }
        .confirmationDialog("Delete dictionary entry?", isPresented: Binding(
            get: { entryToDelete != nil },
            set: { if !$0 { entryToDelete = nil } }
        ), presenting: entryToDelete) { entry in
            Button("Delete", role: .destructive) { deleteEntry(entry) }
        } message: { entry in
            Text("ShoutOut will stop replacing these phrases with “\(entry.phrase)”.")
        }
        .alert("Dictionary error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .background {
            Button("Find dictionary entry") {
                if entry == nil {
                    searchFocused = true
                } else {
                    focusesSearchOnReturn = true
                    selectedEntryID = nil
                }
            }
            .keyboardShortcut("f", modifiers: .command)
            .hidden()

            Button("Add dictionary entry") { editor = ReviewDictionaryEditorTarget(entry: nil) }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(store.loadError != nil)
                .hidden()
        }
        .onChange(of: query) { listPosition = nil }
        .onChange(of: entry?.id, initial: true) {
            if let entry { returnFocusID = entry.id }
        }
    }

    private var entryList: some View {
        let entries = filteredEntries
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if let loadError = store.loadError {
                        unavailableState(loadError)
                    } else if store.entries.isEmpty {
                        emptyState
                    } else if entries.isEmpty {
                        noResultsState
                    } else {
                        ForEach(entries) { entry in
                            entryRow(entry)
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
            .onMoveCommand { direction in
                guard direction == .up || direction == .down,
                      let index = entries.firstIndex(where: { $0.id == focusedRowID }) else { return }
                let next = index + (direction == .down ? 1 : -1)
                guard entries.indices.contains(next) else { return }
                let id = entries[next].id
                proxy.scrollTo(id)
                focusedRowID = id
            }
            .task {
                let id = returnFocusID
                returnFocusID = nil
                if focusesSearchOnReturn {
                    focusesSearchOnReturn = false
                    DispatchQueue.main.async { searchFocused = true }
                } else if let id, entries.contains(where: { $0.id == id }) {
                    proxy.scrollTo(id)
                    DispatchQueue.main.async { focusedRowID = id }
                }
            }
        }
    }

    private func entryRow(_ entry: DictionaryEntry) -> some View {
        Button {
            returnFocusID = entry.id
            selectedEntryID = entry.id
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.phrase)
                        .font(.system(size: 15, weight: .medium))
                        .lineLimit(1)
                    Text(entry.aliases.joined(separator: ", "))
                        .font(.system(size: 13))
                        .foregroundStyle(ReviewTheme.muted)
                        .lineLimit(1)
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
        .focusable()
        .focused($focusedRowID, equals: entry.id)
        .onKeyPress(.return) {
            selectedEntryID = entry.id
            return .handled
        }
        .focusEffectDisabled()
        .overlay {
            RoundedRectangle(cornerRadius: ReviewTheme.navigationRadius)
                .strokeBorder(focusedRowID == entry.id ? ReviewTheme.muted.opacity(0.75) : .clear)
                .allowsHitTesting(false)
        }
        .accessibilityLabel("\(entry.phrase), replaces \(entry.aliases.joined(separator: ", "))")
    }

    private var selectedEntry: DictionaryEntry? {
        store.entries.first(where: { $0.id == selectedEntryID })
    }

    private var filteredEntries: [DictionaryEntry] {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.entries.filter { entry in
            search.isEmpty || entry.phrase.localizedStandardContains(search)
                || entry.aliases.contains { $0.localizedStandardContains(search) }
        }
        .sorted { $0.phrase.localizedStandardCompare($1.phrase) == .orderedAscending }
    }

    private func entryActions(_ entry: DictionaryEntry) -> some View {
        HStack(spacing: 8) {
            ReviewTooltippedButton(title: "Edit entry") {
                editor = ReviewDictionaryEditorTarget(entry: entry)
            } label: { Image(systemName: "pencil") }
                .buttonStyle(ReviewIconButtonStyle())
            ReviewTooltippedButton(title: "Delete entry…") {
                entryToDelete = entry
            } label: { Image(systemName: "trash") }
                .buttonStyle(ReviewIconButtonStyle(tint: Color(red: 1, green: 0.48, blue: 0.52)))
        }
    }

    private func entryDetail(_ entry: DictionaryEntry) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(entry.aliases.indices, id: \.self) { index in
                    let alias = entry.aliases[index]
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(alias)
                            .foregroundStyle(ReviewTheme.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 12))
                            .foregroundStyle(ReviewTheme.muted)
                            .accessibilityHidden(true)
                        Text(entry.phrase)
                            .fontWeight(.semibold)
                            .foregroundStyle(ReviewTheme.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.system(size: 15))
                    .textSelection(.enabled)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Heard \(alias), written \(entry.phrase)")
                    .padding(.vertical, 12)
                    if index < entry.aliases.count - 1 {
                        Rectangle().fill(ReviewTheme.line).frame(height: 1)
                    }
                }
            }
            .padding(.horizontal, 16)
            .background(ReviewTheme.panel, in: RoundedRectangle(cornerRadius: ReviewTheme.navigationRadius))

            VStack(alignment: .leading, spacing: 10) {
                Text("Try dictation")
                    .font(.system(size: 15, weight: .semibold))
                TextField("Dictate a sentence here…", text: $testText, axis: .vertical)
                    .lineLimit(2...4)
                    .accessibilityLabel("Dictation test field")
                    .textFieldStyle(ReviewTextFieldStyle())
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "character.book.closed")
                .font(.system(size: 26))
                .foregroundStyle(tint)
            Text("Add your first word")
                .font(.system(size: 26, weight: .semibold))
            Text("Add words ShoutOut mishears and the spelling you want instead.")
                .font(.system(size: 13))
                .foregroundStyle(ReviewTheme.muted)
            Button("Add entry") { editor = ReviewDictionaryEditorTarget(entry: nil) }
                .buttonStyle(.borderedProminent)
                .modifier(ReviewPrimaryForeground(tint: tint))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 40)
    }

    private var noResultsState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No matching entries").font(.system(size: 18, weight: .semibold))
            Text("Try another word or search for how it is heard.")
                .foregroundStyle(ReviewTheme.muted)
            Button("Clear search") {
                query = ""
                searchFocused = true
            }
            .buttonStyle(.bordered)
        }
        .font(.system(size: 13))
        .padding(.top, 40)
    }

    private func unavailableState(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Saved entries unavailable", systemImage: "exclamationmark.triangle")
                .font(.system(size: 18, weight: .semibold))
            Text(message).font(.system(size: 13)).textSelection(.enabled)
            HStack(spacing: 10) {
                Button("Show File") {
                    NSWorkspace.shared.selectFile(
                        store.fileURL.path,
                        inFileViewerRootedAtPath: store.fileURL.deletingLastPathComponent().path
                    )
                }
                Button("Try Again") { store.reload() }
            }
            .buttonStyle(.bordered)
            .tint(ReviewTheme.text)
        }
        .padding(.top, 32)
    }

    private func deleteEntry(_ entry: DictionaryEntry) {
        do {
            try store.deleteEntry(id: entry.id)
            if selectedEntryID == entry.id { selectedEntryID = nil }
        } catch {
            errorMessage = error.localizedDescription
        }
        entryToDelete = nil
    }
}

private struct ReviewDictionaryEditorTarget: Identifiable {
    let id = UUID()
    let entry: DictionaryEntry?
}

private struct ReviewDictionaryEditor: View {
    @ObservedObject var store: DictionaryStore
    let entry: DictionaryEntry?
    let tint: Color
    let onSaved: (UUID) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var phrase: String
    @State private var aliasesText: String
    @State private var errorMessage: String?
    @FocusState private var aliasesFocused: Bool

    init(store: DictionaryStore, entry: DictionaryEntry?, tint: Color, onSaved: @escaping (UUID) -> Void) {
        self.store = store
        self.entry = entry
        self.tint = tint
        self.onSaved = onSaved
        _phrase = State(initialValue: entry?.phrase ?? "")
        _aliasesText = State(initialValue: entry?.aliases.joined(separator: "\n") ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(entry == nil ? "Add dictionary entry" : "Edit dictionary entry")
                .font(.system(size: 22, weight: .semibold))
            Text("Choose what ShoutOut should replace and how to write it.")
                .font(.system(size: 13))
                .foregroundStyle(ReviewTheme.muted)

            VStack(alignment: .leading, spacing: 7) {
                Text("Replace").font(.system(size: 13, weight: .semibold))
                TextField("web site, web-site", text: $aliasesText, axis: .vertical)
                    .lineLimit(3...5)
                    .focused($aliasesFocused)
                    .accessibilityLabel("Replace phrases")
                    .textFieldStyle(ReviewTextFieldStyle())
                Text("Separate variations with a comma or a new line.")
                    .font(.system(size: 13))
                    .foregroundStyle(ReviewTheme.muted)
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("Write as").font(.system(size: 13, weight: .semibold))
                TextField("website", text: $phrase)
                    .accessibilityLabel("Write as")
                    .textFieldStyle(ReviewTextFieldStyle())
                Text("Matches whole phrases and ignores capitalization.")
                    .font(.system(size: 13))
                    .foregroundStyle(ReviewTheme.muted)
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.bordered)
                    .tint(ReviewTheme.text)
                    .foregroundStyle(ReviewTheme.text)
                Button(entry == nil ? "Add entry" : "Save changes") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(canSave ? tint : .gray)
                    .modifier(ReviewPrimaryForeground(tint: tint))
                    .disabled(!canSave)
            }
        }
        .padding(28)
        .frame(width: 460)
        .background(ReviewTheme.background)
        .foregroundStyle(ReviewTheme.text)
        .tint(tint)
        .onAppear { aliasesFocused = true }
        .onChange(of: aliasesText) { _, _ in errorMessage = nil }
        .onChange(of: phrase) { _, _ in errorMessage = nil }
    }

    private var canSave: Bool {
        !phrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && aliasesText.split(whereSeparator: { $0 == "," || $0 == "\n" }).contains {
                !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
    }

    private func save() {
        do {
            if let entry {
                try store.updateEntry(id: entry.id, phrase: phrase, aliasesText: aliasesText)
                onSaved(entry.id)
            } else {
                let existingIDs = Set(store.entries.map(\.id))
                try store.addEntry(phrase: phrase, aliasesText: aliasesText)
                if let added = store.entries.first(where: { !existingIDs.contains($0.id) }) {
                    onSaved(added.id)
                }
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
