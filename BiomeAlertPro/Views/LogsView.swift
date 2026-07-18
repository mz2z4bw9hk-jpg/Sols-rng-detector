import SwiftUI
import UniformTypeIdentifiers

/// Structured log viewer with level filtering and export.
struct LogsView: View {
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        LogsContent(environment: environment)
    }
}

private struct LogsContent: View {
    @ObservedObject private var logs: LogStore
    @State private var levelFilter: LogLevel?
    @State private var categoryFilter: LogCategory?

    init(environment: AppEnvironment) {
        _logs = ObservedObject(wrappedValue: environment.logs)
    }

    private var filtered: [LogEntry] {
        logs.entries.reversed().filter { entry in
            (levelFilter == nil || entry.level == levelFilter)
                && (categoryFilter == nil || entry.category == categoryFilter)
        }
    }

    var body: some View {
        Group {
            if filtered.isEmpty {
                EmptyState(
                    systemImage: "doc.text.magnifyingglass",
                    title: "No Log Entries",
                    message: "Application activity — startup, connections, webhook deliveries, detections, launches, and errors — is recorded here."
                )
            } else {
                List(filtered) { entry in
                    LogRow(entry: entry)
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle("Logs")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Picker("Level", selection: $levelFilter) {
                    Text("All Levels").tag(LogLevel?.none)
                    ForEach(LogLevel.allCases) { level in
                        Text(level.displayName).tag(LogLevel?.some(level))
                    }
                }
                .pickerStyle(.menu)

                Picker("Category", selection: $categoryFilter) {
                    Text("All Categories").tag(LogCategory?.none)
                    ForEach(LogCategory.allCases) { category in
                        Text(category.displayName).tag(LogCategory?.some(category))
                    }
                }
                .pickerStyle(.menu)

                Button {
                    let text = logs.exportText()
                    _ = Panels.saveData(Data(text.utf8), suggestedName: "BiomeAlertPro-Logs.txt", contentType: .plainText)
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }

                Button(role: .destructive) {
                    logs.clear()
                } label: {
                    Label("Clear", systemImage: "trash")
                }
            }
        }
    }
}

private struct LogRow: View {
    let entry: LogEntry

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: entry.symbol ?? entry.level.symbolName)
                .foregroundStyle(entry.symbol != nil ? Color.accentColor : entry.level.tint)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.message)
                    .font(.callout)
                    .textSelection(.enabled)
                HStack(spacing: 8) {
                    Text(entry.date.formatted(date: .omitted, time: .standard))
                    Text(entry.category.displayName)
                        .padding(.horizontal, 5)
                        .background(.quaternary.opacity(0.5), in: Capsule())
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}
