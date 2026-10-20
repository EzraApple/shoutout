import ShoutOutCore
import SwiftUI

struct DictionaryEntryEditor: View {
    @ObservedObject var store: DictionaryStore
    let entry: DictionaryEntry?

    @Environment(\.dismiss) private var dismiss
    @State private var phrase: String
    @State private var aliasesText: String
    @State private var errorMessage: String?
    @FocusState private var aliasesFocused: Bool

    init(store: DictionaryStore, entry: DictionaryEntry?) {
        self.store = store
        self.entry = entry
        _phrase = State(initialValue: entry?.phrase ?? "")
        _aliasesText = State(initialValue: entry?.aliases.joined(separator: "\n") ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 7) {
                Text(entry == nil ? "Add dictionary entry" : "Edit dictionary entry")
                    .font(.system(.title2, design: .rounded).weight(.heavy))
                Text("Choose what ShoutOut should replace and how to write it.")
                    .font(.subheadline)
                    .foregroundStyle(ShoutOutHomeTheme.muted)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Replace").font(.headline)
                TextField("web site, web-site", text: $aliasesText, axis: .vertical)
                    .lineLimit(3...5)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(ShoutOutHomeTheme.panel)
                    .overlay(ShoutOutHomeTheme.pixelBorder)
                    .focused($aliasesFocused)
                    .accessibilityLabel("Replace phrases")
                Text("Separate variations with a comma or a new line.")
                    .font(.caption)
                    .foregroundStyle(ShoutOutHomeTheme.muted)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Write as").font(.headline)
                TextField("website", text: $phrase)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(ShoutOutHomeTheme.panel)
                    .overlay(ShoutOutHomeTheme.pixelBorder)
                    .accessibilityLabel("Write as")
                Text("Matches whole phrases and ignores capitalization.")
                    .font(.caption)
                    .foregroundStyle(ShoutOutHomeTheme.muted)
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.circle")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 14) {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(HomeSecondaryButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button(entry == nil ? "Add Entry" : "Save Changes") { saveEntry() }
                    .buttonStyle(HomePrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
                    .opacity(canSave ? 1 : 0.45)
            }
        }
        .padding(28)
        .frame(width: 480)
        .background(ShoutOutHomeTheme.background)
        .foregroundStyle(ShoutOutHomeTheme.ink)
        .environment(\.colorScheme, .light)
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

    private func saveEntry() {
        do {
            if let entry {
                try store.updateEntry(id: entry.id, phrase: phrase, aliasesText: aliasesText)
            } else {
                try store.addEntry(phrase: phrase, aliasesText: aliasesText)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
