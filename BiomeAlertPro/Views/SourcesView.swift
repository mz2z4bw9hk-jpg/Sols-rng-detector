import SwiftUI

/// Configure where alerts come from: Discord OAuth identity, an official
/// Discord bot (Gateway), and the local webhook listener endpoint.
struct SourcesView: View {
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        SourcesContent(environment: environment)
    }
}

private struct SourcesContent: View {
    @EnvironmentObject private var environment: AppEnvironment
    @StateObject private var viewModel: SourcesViewModel
    @ObservedObject private var oauth: DiscordOAuthService
    @ObservedObject private var settings: SettingsStore

    init(environment: AppEnvironment) {
        _viewModel = StateObject(wrappedValue: SourcesViewModel(environment: environment))
        _oauth = ObservedObject(wrappedValue: environment.oauth)
        _settings = ObservedObject(wrappedValue: environment.settings)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                screenWatcherSection
                oauthSection
                botSection
                listenerSection
            }
            .padding(20)
        }
        .navigationTitle("Sources")
    }

    // MARK: - Screen watcher

    private var screenWatcherSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                StatusBadge(kind: screenWatcherBadgeKind, text: environment.screenWatcherState.displayName)

                Text("Watches your own Discord window using screen capture + on-device OCR. When a new Roblox private-server link for one of your selected biomes appears, Roblox launches instantly from the extracted link. 100% local and read-only — nothing is sent to Discord and your account is never automated. Ideal for alert servers you can't add a bot to.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Toggle("Watch my Discord window", isOn: $settings.screenWatcherEnabled)
                    .onChange(of: settings.screenWatcherEnabled) { _, _ in
                        environment.applyScreenWatcherSetting()
                        if !environment.isMonitoring && settings.screenWatcherEnabled {
                            environment.startMonitoring()
                        }
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Label("Grant Screen Recording when macOS asks (System Settings → Privacy & Security → Screen Recording), then relaunch the app.", systemImage: "1.circle")
                    Label("Keep Discord open with the alert channel visible — behind other windows is fine, minimized is not.", systemImage: "2.circle")
                    Label("Choose which biomes auto-launch in Settings → Auto-Launch Biomes.", systemImage: "3.circle")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(6)
        } label: {
            SectionTitle(title: "Screen Watcher (Discord window OCR)", systemImage: "eye")
        }
    }

    private var screenWatcherBadgeKind: StatusBadge.Kind {
        switch environment.screenWatcherState {
        case .watching: return .ok
        case .waitingForDiscord: return .warning
        case .failed: return .error
        case .stopped: return .neutral
        }
    }

    // MARK: - Discord OAuth

    private var oauthSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                if let user = oauth.user {
                    HStack(spacing: 12) {
                        Image(systemName: "person.crop.circle.badge.checkmark")
                            .font(.system(size: 28))
                            .foregroundStyle(.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(user.displayName).font(.headline)
                            Text("Connected via Discord OAuth (identify scope)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Sign Out", role: .destructive) {
                            viewModel.signOut()
                        }
                    }
                } else {
                    Text("Sign in with your own Discord application (OAuth2 + PKCE). Only the official `identify` scope is requested — the app never reads your account's messages and never uses user tokens.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    TextField("Discord Application Client ID", text: $viewModel.clientIDInput)
                        .textFieldStyle(.roundedBorder)
                    SecureField("Client Secret (optional, for confidential apps)", text: $viewModel.clientSecretInput)
                        .textFieldStyle(.roundedBorder)

                    HStack {
                        Button {
                            viewModel.signIn()
                        } label: {
                            Label("Sign in with Discord", systemImage: "person.badge.key")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(viewModel.clientIDInput.trimmingCharacters(in: .whitespaces).isEmpty)

                        if oauth.isAuthorizing {
                            ProgressView().controlSize(.small)
                        }
                    }
                }
                if let status = oauth.statusMessage {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .padding(6)
        } label: {
            SectionTitle(title: "Discord Account (OAuth)", systemImage: "person.crop.circle")
        }
    }

    // MARK: - Discord bot (Gateway)

    private var botSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                StatusBadge(kind: botBadgeKind, text: environment.gatewayStatus.displayName)

                Text("Receive channel messages the official way: create a bot in the Discord Developer Portal, enable the Message Content intent, invite it to your alert server, and paste its bot token. The token is stored in the macOS Keychain.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if environment.botTokenConfigured {
                    HStack {
                        Label("Bot token saved in Keychain", systemImage: "key.fill")
                            .font(.callout)
                        Spacer()
                        Button("Disconnect & Remove Token", role: .destructive) {
                            viewModel.disconnectBot()
                        }
                    }
                } else {
                    SecureField("Bot token", text: $viewModel.botTokenInput)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        viewModel.connectBot()
                    } label: {
                        Label("Connect Bot", systemImage: "link")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.botTokenInput.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                if let info = viewModel.infoMessage {
                    Text(info).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(6)
        } label: {
            SectionTitle(title: "Discord Bot (official Gateway)", systemImage: "bubble.left.and.bubble.right")
        }
    }

    private var botBadgeKind: StatusBadge.Kind {
        switch environment.gatewayStatus {
        case .connected: return .ok
        case .connecting, .reconnecting: return .warning
        case .failed: return .error
        case .disconnected: return .neutral
        }
    }

    // MARK: - Local webhook listener

    private var listenerSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                StatusBadge(kind: listenerBadgeKind, text: environment.listenerState.displayName)

                Text("Biome Alert Pro hosts a local HTTP endpoint that accepts Discord-webhook-style JSON. Point any of your own alert forwarders at it. It binds to 127.0.0.1 unless LAN access is enabled in Settings.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Toggle("Enable webhook listener", isOn: $settings.listenerEnabled)
                    .onChange(of: settings.listenerEnabled) { _, _ in
                        environment.restartListenerIfRunning()
                    }

                HStack {
                    Text("Port")
                    TextField("8787", value: $settings.listenerPort, format: .number.grouping(.never))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)
                    Button("Apply") {
                        environment.restartListenerIfRunning()
                    }
                }

                HStack {
                    SecureField(
                        environment.listenerSecretConfigured ? "Shared secret (configured)" : "Shared secret (optional)",
                        text: $viewModel.listenerSecretInput
                    )
                    .textFieldStyle(.roundedBorder)
                    Button("Save Secret") {
                        viewModel.applyListenerSecret()
                    }
                }

                DisclosureGroup("Example: deliver an alert with curl") {
                    Text(viewModel.curlExample)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                }
                .font(.callout)
            }
            .padding(6)
        } label: {
            SectionTitle(title: "Webhook Listener (local endpoint)", systemImage: "antenna.radiowaves.left.and.right")
        }
    }

    private var listenerBadgeKind: StatusBadge.Kind {
        switch environment.listenerState {
        case .listening: return .ok
        case .starting: return .warning
        case .failed: return .error
        case .stopped: return .neutral
        }
    }
}
