import SwiftUI

/// The user-editable keyword database, grouped by category.
struct KeywordsView: View {
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        KeywordsContent(environment: environment)
    }
}

private struct KeywordsContent: View {
    @StateObject private var viewModel: KeywordsViewModel
    @ObservedObject private var store: KeywordStore
    @ObservedObject private var settings: SettingsStore

    init(environment: AppEnvironment) {
        _viewModel = StateObject(wrappedValue: KeywordsViewModel(store: environment.keywords))
        _store = ObservedObject(wrappedValue: environment.keywords)
        _settings = ObservedObject(wrappedValue: environment.settings)
    }

    var body: some View {
        List(selection: $viewModel.selection) {
            ForEach(KeywordCategory.allCases) { category in
                let keywords = store.keywords(in: category)
                if !keywords.isEmpty || category == .custom {
                    Section {
                        ForEach(keywords) { keyword in
                            KeywordRow(keyword: keyword) { enabled in
                                store.setEnabled(enabled, id: keyword.id)
                            }
                            .tag(keyword.id)
                        }
                    } header: {
                        Label(category.displayName, systemImage: category.symbolName)
                    }
                }
            }
        }
        .navigationTitle("Keywords")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    viewModel.presentAddForm()
                } label: {
                    Label("Add Keyword", systemImage: "plus")
                }
                Button(role: .destructive) {
                    viewModel.deleteSelection()
                } label: {
                    Label("Delete Selected", systemImage: "trash")
                }
                .disabled(viewModel.selection.isEmpty)

                Menu {
                    Button("Import Database…") { viewModel.importDatabase() }
                    Button("Export Database…") { viewModel.exportDatabase() }
                    Divider()
                    Button("Restore Defaults", role: .destructive) { viewModel.restoreDefaults() }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $viewModel.isPresentingForm) {
            KeywordFormSheet(viewModel: viewModel)
        }
        .safeAreaInset(edge: .bottom) {
            footer
        }
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                Toggle("Fuzzy matching (tolerate small typos)", isOn: $settings.fuzzyMatchingEnabled)
                Spacer()
                if let status = viewModel.statusMessage {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("\(store.enabledKeywords.count) of \(store.keywords.count) enabled")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
        }
        .background(.bar)
    }
}

private struct KeywordRow: View {
    let keyword: Keyword
    let onToggle: @MainActor (Bool) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(get: { keyword.isEnabled }, set: onToggle))
                .toggleStyle(.checkbox)
                .labelsHidden()

            Text(keyword.text)
                .font(.body.monospaced())
                .foregroundStyle(keyword.isEnabled ? .primary : .tertiary)

            Spacer()

            Text(keyword.matchMode.displayName)
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary.opacity(0.6), in: Capsule())

            Text(String(format: "weight %.2f", keyword.weight))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
        .padding(.vertical, 2)
    }
}

private struct KeywordFormSheet: View {
    @ObservedObject var viewModel: KeywordsViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Keyword")
                .font(.title3.weight(.semibold))

            TextField("Keyword, phrase, or regex", text: $viewModel.newText)
                .textFieldStyle(.roundedBorder)

            Picker("Category", selection: $viewModel.newCategory) {
                ForEach(KeywordCategory.allCases) { category in
                    Text(category.displayName).tag(category)
                }
            }

            Picker("Match mode", selection: $viewModel.newMatchMode) {
                ForEach(KeywordMatchMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(String(format: "Weight: %.2f", viewModel.newWeight))
                    .font(.callout)
                Slider(value: $viewModel.newWeight, in: 0.05...1.0)
                Text("Higher weight = stronger contribution to the alert confidence score.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let message = viewModel.statusMessage {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add") {
                    if viewModel.submitForm() {
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.newText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}
