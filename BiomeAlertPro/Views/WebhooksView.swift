import SwiftUI

/// Manage outbound Discord webhooks (add/edit/delete/test, delivery status).
struct WebhooksView: View {
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        WebhooksContent(environment: environment)
    }
}

private struct WebhooksContent: View {
    @EnvironmentObject private var environment: AppEnvironment
    @StateObject private var viewModel: WebhooksViewModel
    @ObservedObject private var store: WebhookStore
    @ObservedObject private var settings: SettingsStore

    init(environment: AppEnvironment) {
        _viewModel = StateObject(wrappedValue: WebhooksViewModel(store: environment.webhooks))
        _store = ObservedObject(wrappedValue: environment.webhooks)
        _settings = ObservedObject(wrappedValue: environment.settings)
    }

    var body: some View {
        Group {
            if store.webhooks.isEmpty {
                EmptyState(
                    systemImage: "link.badge.plus",
                    title: "No Webhooks Yet",
                    message: "Add a Discord webhook URL to forward alerts into your own server channel, or to test connectivity. Webhook URLs are stored in the macOS Keychain."
                )
            } else {
                webhookList
            }
        }
        .navigationTitle("Webhooks")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    viewModel.presentAddForm()
                } label: {
                    Label("Add Webhook", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $viewModel.isPresentingForm) {
            WebhookFormSheet(viewModel: viewModel)
        }
        .safeAreaInset(edge: .bottom) {
            forwardingFooter
        }
    }

    private var webhookList: some View {
        List {
            ForEach(store.webhooks) { webhook in
                WebhookRow(
                    webhook: webhook,
                    isTesting: viewModel.testingID == webhook.id,
                    testResult: viewModel.testResults[webhook.id],
                    isEnabled: Binding(
                        get: { webhook.isEnabled },
                        set: { store.setEnabled($0, id: webhook.id) }
                    ),
                    onTest: { viewModel.runTest(for: webhook) },
                    onEdit: { viewModel.presentEditForm(for: webhook) },
                    onDelete: { store.delete(id: webhook.id) }
                )
            }
        }
        .listStyle(.inset)
    }

    private var forwardingFooter: some View {
        VStack(spacing: 0) {
            Divider()
            Toggle("Forward detected alerts to all enabled webhooks", isOn: $settings.forwardAlertsToWebhooks)
                .padding(12)
        }
        .background(.bar)
    }
}

private struct WebhookRow: View {
    let webhook: WebhookConfig
    let isTesting: Bool
    let testResult: String?
    @Binding var isEnabled: Bool
    let onTest: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Toggle("", isOn: $isEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()

                VStack(alignment: .leading, spacing: 2) {
                    Text(webhook.name).font(.headline)
                    HStack(spacing: 6) {
                        StatusBadge(kind: badgeKind, text: webhook.lastDeliveryState.displayName)
                        if let date = webhook.lastDeliveryDate {
                            Text(date.formatted(.relative(presentation: .named)))
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                Spacer()

                if isTesting {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Test") { onTest() }
                        .buttonStyle(.bordered)
                }
                Button {
                    onEdit()
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                .help("Edit webhook")
            }

            if let testResult {
                Text(testResult)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            if let detail = webhook.lastDeliveryDetail, webhook.lastDeliveryState == .failed {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button("Test Connection") { onTest() }
            Button("Edit…") { onEdit() }
            Divider()
            Button("Delete", role: .destructive) { onDelete() }
        }
    }

    private var badgeKind: StatusBadge.Kind {
        switch webhook.lastDeliveryState {
        case .ok: return .ok
        case .retrying: return .warning
        case .failed: return .error
        case .never: return .neutral
        }
    }
}

private struct WebhookFormSheet: View {
    @ObservedObject var viewModel: WebhooksViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(viewModel.formTitle)
                .font(.title3.weight(.semibold))

            TextField("Name (e.g. “Biome Alerts Channel”)", text: $viewModel.nameInput)
                .textFieldStyle(.roundedBorder)

            SecureField("https://discord.com/api/webhooks/…", text: $viewModel.urlInput)
                .textFieldStyle(.roundedBorder)

            Text("Webhook URLs contain a secret token, so they are stored in the macOS Keychain and never logged.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let message = viewModel.validationMessage {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    if viewModel.submitForm() {
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}
