import AppKit
import ShoutOutCore
import SwiftUI

struct DictionaryView: View {
    @ObservedObject var store: DictionaryStore

    @State private var query = ""
    @State private var editor: DictionaryEditorTarget?
    @State private var entryToDelete: DictionaryEntry?
    @State private var errorMessage: String?
    @State private var previewText = ""
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageHeader(
                title: "Dictionary",
                subtitle: "Names, acronyms, and words. Written your way."
            )

            HStack(spacing: 14) {
                searchField
                Button {
                    editor = DictionaryEditorTarget(entry: nil)
                } label: {
                    Label("Add Entry", systemImage: "plus")
                }
                .buttonStyle(HomePrimaryButtonStyle())
                .keyboardShortcut("n", modifiers: .command)
                .disabled(store.loadError != nil)
                .opacity(store.loadError == nil ? 1 : 0.45)
            }

            entriesPanel
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.circle")
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            if store.loadError == nil {
                previewPanel
            }

            Label("Saved on this Mac. Applied before text cleanup to every dictation.", systemImage: "lock")
                .font(.caption)
                .foregroundStyle(ShoutOutHomeTheme.muted)
        }
        .frame(maxWidth: 850, alignment: .leading)
        .sheet(item: $editor) { target in
            DictionaryEntryEditor(store: store, entry: target.entry)
        }
        .alert("Delete dictionary entry?", isPresented: isConfirmingDelete, presenting: entryToDelete) { entry in
            Button("Cancel", role: .cancel) { entryToDelete = nil }
            Button("Delete", role: .destructive) { deleteEntry(entry) }
        } message: { entry in
            Text("ShoutOut will stop replacing these phrases with “\(entry.phrase)”.")
        }
        .background {
            Button("Find dictionary entry") { searchFocused = true }
                .keyboardShortcut("f", modifiers: .command)
                .hidden()
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(ShoutOutHomeTheme.muted)
            TextField("Search words or replacements…", text: $query)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .accessibilityLabel("Search dictionary")
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear dictionary search")
            }
        }
        .padding(11)
        .background(ShoutOutHomeTheme.panel)
        .overlay(ShoutOutHomeTheme.pixelBorder)
    }

    private var entriesPanel: some View {
        HomePanel {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(store.loadError == nil
                         ? "\(store.entries.count) \(store.entries.count == 1 ? "entry" : "entries")"
                         : "Saved entries unavailable")
                        .font(.headline)
                    Spacer()
                    Text("WHOLE PHRASES · ANY CASE")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(ShoutOutHomeTheme.muted)
                }

                if let loadError = store.loadError {
                    Label(loadError, systemImage: "exclamationmark.circle")
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 14) {
                        Button("Show File") {
                            NSWorkspace.shared.selectFile(
                                store.fileURL.path,
                                inFileViewerRootedAtPath: store.fileURL.deletingLastPathComponent().path
                            )
                        }
                        Button("Try Again") { store.reload() }
                    }
                    .buttonStyle(HomeSecondaryButtonStyle())
                } else if store.entries.isEmpty {
                    emptyState
                } else if filteredEntries.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No matching entries")
                            .font(.headline)
                        Text("Try another word or search for how it is heard.")
                            .foregroundStyle(ShoutOutHomeTheme.muted)
                    }
                    .padding(.vertical, 20)
                } else {
                    HStack(spacing: 16) {
                        columnLabel("REPLACE")
                        Image(systemName: "arrow.right").hidden()
                        columnLabel("WRITE AS")
                        Color.clear.frame(width: 66, height: 1)
                    }
                    ForEach(filteredEntries) { entry in
                        entryRow(entry)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Get the little things right.", systemImage: "character.book.closed")
                .font(.title3.weight(.bold))
            Text("Add words ShoutOut mishears and the spelling you want instead.")
                .foregroundStyle(ShoutOutHomeTheme.muted)
            HStack(spacing: 12) {
                Text("web site")
                    .foregroundStyle(ShoutOutHomeTheme.muted)
                Image(systemName: "arrow.right")
                Text("website").fontWeight(.semibold)
            }
            .padding(12)
            .background(ShoutOutHomeTheme.panelBlue.opacity(0.35))
            Text("For a capitalization fix, use the same word on both sides.")
                .font(.caption)
                .foregroundStyle(ShoutOutHomeTheme.muted)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func entryRow(_ entry: DictionaryEntry) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(entry.aliases.isEmpty ? "No replacement phrases" : entry.aliases.joined(separator: ", "))
                .foregroundStyle(ShoutOutHomeTheme.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(3)
                .help(entry.aliases.joined(separator: ", "))
            Image(systemName: "arrow.right")
                .font(.caption)
                .foregroundStyle(ShoutOutHomeTheme.muted)
            Text(entry.phrase)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(3)
                .help(entry.phrase)
            HStack(spacing: 14) {
                Button {
                    editor = DictionaryEditorTarget(entry: entry)
                } label: {
                    Image(systemName: "pencil")
                }
                .help("Edit \(entry.phrase)")
                .accessibilityLabel("Edit \(entry.phrase)")
                Button {
                    entryToDelete = entry
                } label: {
                    Image(systemName: "trash")
                }
                .help("Delete \(entry.phrase)")
                .accessibilityLabel("Delete \(entry.phrase)")
            }
            .buttonStyle(.borderless)
            .frame(width: 66, alignment: .trailing)
        }
        .padding(.vertical, 12)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(ShoutOutHomeTheme.ink.opacity(0.12))
                .frame(height: 1)
        }
    }

    private var previewPanel: some View {
        HomePanel(background: ShoutOutHomeTheme.panelMintLight) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Try your dictionary")
                    .font(.headline)
                Text("Test your saved replacements. Text cleanup runs afterward when enabled.")
                    .font(.subheadline)
                    .foregroundStyle(ShoutOutHomeTheme.muted)
                TextField("For example: open the web site", text: $previewText, axis: .vertical)
                    .lineLimit(2...4)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(ShoutOutHomeTheme.panel)
                    .overlay(Rectangle().stroke(ShoutOutHomeTheme.ink.opacity(0.3)))
                    .accessibilityLabel("Test dictionary sentence")
                if !previewText.isEmpty {
                    Text("RESULT")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(ShoutOutHomeTheme.muted)
                    Text(DictionaryReplacer.replace(previewText, entries: store.entries))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var filteredEntries: [DictionaryEntry] {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.entries.filter { entry in
            search.isEmpty || entry.phrase.localizedStandardContains(search)
                || entry.aliases.contains { $0.localizedStandardContains(search) }
        }.sorted { $0.phrase.localizedStandardCompare($1.phrase) == .orderedAscending }
    }

    private var isConfirmingDelete: Binding<Bool> {
        Binding(get: { entryToDelete != nil }, set: { if !$0 { entryToDelete = nil } })
    }

    private func deleteEntry(_ entry: DictionaryEntry) {
        do {
            try store.deleteEntry(id: entry.id)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        entryToDelete = nil
    }

    private func columnLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundStyle(ShoutOutHomeTheme.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DictionaryEditorTarget: Identifiable {
    let id = UUID()
    let entry: DictionaryEntry?
}
