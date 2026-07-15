import Foundation

/// Form state and actions for the Sources screen (OAuth, bot, listener).
@MainActor
final class SourcesViewModel: ObservableObject {
    @Published var clientIDInput: String = ""
    @Published var clientSecretInput: String = ""
    @Published var botTokenInput: String = ""
    @Published var listenerSecretInput: String = ""
    @Published var infoMessage: String?

    private let environment: AppEnvironment

    init(environment: AppEnvironment) {
        self.environment = environment
        clientIDInput = environment.settings.discordClientID
    }

    // MARK: - OAuth

    func signIn() {
        environment.settings.discordClientID = clientIDInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if !clientSecretInput.isEmpty {
            environment.oauth.setClientSecret(clientSecretInput)
            clientSecretInput = ""
        }
        environment.oauth.beginSignIn()
    }

    func signOut() {
        environment.oauth.signOut()
    }

    // MARK: - Bot

    func connectBot() {
        let token = botTokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            infoMessage = "Paste your bot token first."
            return
        }
        environment.saveBotToken(token)
        botTokenInput = ""
        infoMessage = nil
        if !environment.isMonitoring {
            environment.startMonitoring()
        }
    }

    func disconnectBot() {
        environment.removeBotToken()
    }

    // MARK: - Listener

    func applyListenerSecret() {
        environment.saveListenerSecret(listenerSecretInput)
        listenerSecretInput = ""
        infoMessage = "Shared secret updated."
    }

    var curlExample: String {
        let port = environment.settings.listenerPort
        var header = ""
        if environment.listenerSecretConfigured {
            header = " \\\n  -H 'X-BiomeAlert-Secret: <your secret>'"
        }
        return """
        curl -X POST http://127.0.0.1:\(port)/alert \\
          -H 'Content-Type: application/json'\(header) \\
          -d '{"content": "GLITCHED biome! https://www.roblox.com/games/15532962292?privateServerLinkCode=abc123"}'
        """
    }
}
