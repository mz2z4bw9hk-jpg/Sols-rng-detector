import AppKit
import SwiftUI

/// Searchable, sortable, exportable alert history.
struct HistoryView: View {
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        HistoryContent(environment: environment)
    }
}

private struct HistoryContent: View {
    @EnvironmentObject private var environment: AppEnvironment
    @StateObject private var viewModel: HistoryViewModel
    @ObservedObject private var store: HistoryStore
    @State private var isConfirmingClear = false

    init(environment: AppEnvironment) {
        _viewModel = StateObject(wrappedValue: HistoryViewModel(store: environment.history))
        _store = ObservedObject(wrappedValue: environment.history)
    }

    var body: some View {
        Group {
            if store.records.isEmpty {
                EmptyState(
                    systemImage: "clock.arrow.circlepath",
                    title: "No Alerts Yet",
                    message: "Detected biome alerts will appear here with their source, matched keywords, latency, and launch status. Try the Test Alert button on the Dashboard."
                )
            } else {
                table
            }
        }
        .navigationTitle("Alert History")
        .searchable(text: $viewModel.searchText, prompt: "Search alerts, biomes, keywords…")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Picker("Filter", selection: $viewModel.filter) {
                    ForEach(HistoryViewModel.BiomeFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.menu)

                Menu {
                    Button("Export CSV…") { viewModel.exportCSV() }
                    Button("Export JSON…") { viewModel.exportJSON() }
                    Divider()
                    Button("Delete Selected", role: .destructive) { viewModel.deleteSelection() }
                        .disabled(viewModel.selection.isEmpty)
                    Button("Clear All…", role: .destructive) { isConfirmingClear = true }
                } label: {
                    Label("Actions", systemImage: "ellipsis.circle")
                }
            }
        }
        .confirmationDialog(
            "Delete all \(store.records.count) alert records?",
            isPresented: $isConfirmingClear,
            titleVisibility: .visible
        ) {
            Button("Clear All", role: .destructive) { viewModel.clearAll() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var table: some View {
        Table(viewModel.filteredRecords(), selection: $viewModel.selection, sortOrder: $viewModel.sortOrder) {
            TableColumn("Time", value: \.date) { record in
                Text(record.date.formatted(date: .abbreviated, time: .standard))
            }
            .width(min: 130, ideal: 150)

            TableColumn("Biome") { record in
                HStack(spacing: 4) {
                    if record.isRareBiome {
                        Image(systemName: "sparkles").foregroundStyle(.purple)
                    }
                    Text(record.biome ?? "—")
                }
            }
            .width(min: 80, ideal: 110)

            TableColumn("Source", value: \.source)
                .width(min: 90, ideal: 120)

            TableColumn("Channel") { record in
                Text(record.channel.map { "#\($0)" } ?? "—")
                    .foregroundStyle(record.channel == nil ? .tertiary : .secondary)
                    .lineLimit(1)
            }
            .width(min: 80, ideal: 120)

            TableColumn("Keywords") { record in
                Text(record.matchedKeywords.joined(separator: ", "))
                    .lineLimit(1)
                    .help(record.matchedKeywords.joined(separator: ", "))
            }
            .width(min: 100, ideal: 160)

            TableColumn("Confidence", value: \.confidence) { record in
                Text(String(format: "%.0f%%", record.confidence * 100))
                    .monospacedDigit()
            }
            .width(min: 70, ideal: 80)

            TableColumn("Latency", value: \.latencyMs) { record in
                Text(String(format: "%.0f ms", record.latencyMs))
                    .monospacedDigit()
            }
            .width(min: 60, ideal: 80)

            TableColumn("Launch") { record in
                HStack(spacing: 4) {
                    Image(systemName: record.launchStatus.symbolName)
                        .foregroundStyle(record.launchStatus == .launched ? .green : .secondary)
                    Text(record.launchStatus.displayName)
                        .foregroundStyle(.secondary)
                }
            }
            .width(min: 90, ideal: 110)

            TableColumn("Link") { record in
                if let link = record.robloxLink {
                    Button {
                        environment.launchLink(link)
                    } label: {
                        Label("Join", systemImage: "play.fill")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help(link)
                } else {
                    Text("—").foregroundStyle(.tertiary)
                }
            }
            .width(min: 70, ideal: 80)
        }
        .contextMenu(forSelectionType: UUID.self) { ids in
            if ids.count == 1,
               let record = environment.history.records.first(where: { ids.contains($0.id) }),
               let link = record.robloxLink {
                Button("Copy Roblox Link") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(link, forType: .string)
                }
                Button("Join Again") {
                    environment.launchLink(link)
                }
                Divider()
            }
            Button("Delete", role: .destructive) {
                environment.history.delete(ids: ids)
            }
        }
    }
}
