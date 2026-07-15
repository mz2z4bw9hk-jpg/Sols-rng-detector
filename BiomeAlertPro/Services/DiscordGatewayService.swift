import Foundation

/// Connection state of the Discord bot Gateway session.
enum GatewayStatus: Sendable, Equatable {
    case disconnected
    case connecting
    case connected(botName: String)
    case reconnecting(attempt: Int)
    case failed(String)

    var displayName: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting…"
        case .connected(let name): return "Connected as \(name)"
        case .reconnecting(let attempt): return "Reconnecting (attempt \(attempt))…"
        case .failed(let message): return "Failed: \(message)"
        }
    }

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
}

/// Official Discord *bot* Gateway client (WebSocket, API v10).
///
/// This is Discord's supported way for an application to receive messages:
/// the user creates a bot in the Discord Developer Portal, invites it to
/// their alert server, and pastes its bot token here. No user tokens, no
/// self-botting — only the documented Gateway protocol with identify,
/// heartbeating, resume, and exponential-backoff reconnects.
actor DiscordGatewayService {
    nonisolated let events: AsyncStream<IncomingEvent>
    private let eventContinuation: AsyncStream<IncomingEvent>.Continuation

    private let session: URLSession
    private var socket: URLSessionWebSocketTask?
    private var pumpTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?

    private var token: String?
    private var shouldRun = false
    private var sequence: Int?
    private var sessionID: String?
    private var resumeGatewayURL: String?
    private var reconnectAttempt = 0

    private var statusHandler: (@Sendable (GatewayStatus) -> Void)?
    private var logHandler: (@Sendable (LogLevel, String) -> Void)?

    private static let defaultGatewayURL = "wss://gateway.discord.gg/?v=10&encoding=json"
    /// GUILDS (1<<0) | GUILD_MESSAGES (1<<9) | MESSAGE_CONTENT (1<<15)
    private static let intents = 33_281

    init() {
        (events, eventContinuation) = AsyncStream.makeStream(of: IncomingEvent.self)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        session = URLSession(configuration: configuration)
    }

    func setHandlers(
        status: @escaping @Sendable (GatewayStatus) -> Void,
        log: @escaping @Sendable (LogLevel, String) -> Void
    ) {
        statusHandler = status
        logHandler = log
    }

    // MARK: - Lifecycle

    func start(token: String) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            statusHandler?(.failed("Bot token is empty"))
            return
        }
        stopInternal()
        self.token = trimmed
        shouldRun = true
        reconnectAttempt = 0
        openConnection()
    }

    func stop() {
        shouldRun = false
        stopInternal()
        statusHandler?(.disconnected)
        logHandler?(.info, "Discord Gateway disconnected")
    }

    private func stopInternal() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
        pumpTask?.cancel()
        pumpTask = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
    }

    private func openConnection() {
        guard shouldRun else { return }
        let urlString = resumeGatewayURL.map { $0 + "/?v=10&encoding=json" } ?? Self.defaultGatewayURL
        guard let url = URL(string: urlString) else {
            statusHandler?(.failed("Invalid gateway URL"))
            return
        }
        statusHandler?(reconnectAttempt == 0 ? .connecting : .reconnecting(attempt: reconnectAttempt))

        let task = session.webSocketTask(with: url)
        socket = task
        task.resume()
        pumpTask = Task { await self.pump(task) }
    }

    /// Receive loop: runs until the socket errors or is cancelled.
    private func pump(_ task: URLSessionWebSocketTask) async {
        while shouldRun && socket === task {
            do {
                let message = try await task.receive()
                switch message {
                case .string(let text):
                    await handleGatewayMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        await handleGatewayMessage(text)
                    }
                @unknown default:
                    break
                }
            } catch {
                guard shouldRun, socket === task else { return }
                await handleDisconnect(task: task, error: error)
                return
            }
        }
    }

    private func handleDisconnect(task: URLSessionWebSocketTask, error: Error) async {
        heartbeatTask?.cancel()
        heartbeatTask = nil

        let closeCode = task.closeCode.rawValue
        // 4004 = authentication failed; retrying would spam Discord.
        if closeCode == 4004 {
            shouldRun = false
            socket = nil
            statusHandler?(.failed("Invalid bot token"))
            logHandler?(.error, "Gateway rejected the bot token (close code 4004)")
            return
        }
        // Codes that invalidate the session for resuming.
        if [4007, 4009].contains(closeCode) {
            sessionID = nil
            resumeGatewayURL = nil
        }

        socket = nil
        reconnectAttempt += 1
        let delay = min(pow(2.0, Double(reconnectAttempt)), 60) + Double.random(in: 0...1)
        statusHandler?(.reconnecting(attempt: reconnectAttempt))
        logHandler?(.warning, "Gateway connection lost (\(error.localizedDescription)) — retrying in \(Int(delay))s")

        try? await Task.sleep(for: .seconds(delay))
        guard shouldRun else { return }
        openConnection()
    }

    // MARK: - Protocol handling

    private func handleGatewayMessage(_ text: String) async {
        guard let data = text.data(using: .utf8),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let opcode = payload["op"] as? Int else { return }

        if let seq = payload["s"] as? Int {
            sequence = seq
        }
        let eventData = payload["d"] as? [String: Any]

        switch opcode {
        case 10: // HELLO
            let interval = (eventData?["heartbeat_interval"] as? Double) ?? 41_250
            startHeartbeat(intervalMs: interval)
            if sessionID != nil {
                await sendResume()
            } else {
                await sendIdentify()
            }

        case 0: // DISPATCH
            let eventName = payload["t"] as? String
            switch eventName {
            case "READY":
                sessionID = eventData?["session_id"] as? String
                resumeGatewayURL = eventData?["resume_gateway_url"] as? String
                let botName = ((eventData?["user"] as? [String: Any])?["username"] as? String) ?? "bot"
                reconnectAttempt = 0
                statusHandler?(.connected(botName: botName))
                logHandler?(.info, "Gateway ready — connected as \(botName)")
            case "RESUMED":
                reconnectAttempt = 0
                logHandler?(.info, "Gateway session resumed")
            case "MESSAGE_CREATE":
                if let eventData {
                    emitMessage(eventData)
                }
            default:
                break
            }

        case 1: // Server requests immediate heartbeat.
            await sendHeartbeat()

        case 7: // RECONNECT — close and resume.
            logHandler?(.info, "Gateway asked us to reconnect")
            socket?.cancel(with: .goingAway, reason: nil)
            socket = nil
            reconnectAttempt += 1
            openConnection()

        case 9: // INVALID SESSION
            let resumable = (payload["d"] as? Bool) ?? false
            if !resumable {
                sessionID = nil
                resumeGatewayURL = nil
            }
            logHandler?(.warning, "Gateway session invalid (resumable: \(resumable)) — re-identifying")
            try? await Task.sleep(for: .seconds(Double.random(in: 1...4)))
            socket?.cancel(with: .goingAway, reason: nil)
            socket = nil
            openConnection()

        case 11: // HEARTBEAT ACK
            break

        default:
            break
        }
    }

    private func emitMessage(_ message: [String: Any]) {
        let content = (message["content"] as? String) ?? ""

        var embedParts: [String] = []
        for embed in (message["embeds"] as? [[String: Any]]) ?? [] {
            if let title = embed["title"] as? String { embedParts.append(title) }
            if let description = embed["description"] as? String { embedParts.append(description) }
            if let url = embed["url"] as? String { embedParts.append(url) }
            for field in (embed["fields"] as? [[String: Any]]) ?? [] {
                if let name = field["name"] as? String { embedParts.append(name) }
                if let value = field["value"] as? String { embedParts.append(value) }
            }
        }
        let embedText = embedParts.joined(separator: "\n")
        guard !content.isEmpty || !embedText.isEmpty else { return }

        let sender = (message["author"] as? [String: Any])?["username"] as? String
        eventContinuation.yield(IncomingEvent(
            id: message["id"] as? String,
            source: .discordBot,
            sender: sender,
            content: content,
            embedText: embedText
        ))
    }

    // MARK: - Outbound frames

    private func startHeartbeat(intervalMs: Double) {
        heartbeatTask?.cancel()
        let interval = max(intervalMs, 1_000) / 1_000
        heartbeatTask = Task { [weak self] in
            // Jitter the first beat per the Gateway spec.
            try? await Task.sleep(for: .seconds(interval * Double.random(in: 0...1)))
            while !Task.isCancelled {
                await self?.sendHeartbeat()
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    private func sendHeartbeat() async {
        await sendJSON(["op": 1, "d": sequence as Any])
    }

    private func sendIdentify() async {
        guard let token else { return }
        await sendJSON([
            "op": 2,
            "d": [
                "token": token,
                "intents": Self.intents,
                "properties": [
                    "os": "macOS",
                    "browser": "BiomeAlertPro",
                    "device": "BiomeAlertPro"
                ]
            ]
        ])
    }

    private func sendResume() async {
        guard let token, let sessionID else {
            await sendIdentify()
            return
        }
        await sendJSON([
            "op": 6,
            "d": [
                "token": token,
                "session_id": sessionID,
                "seq": sequence ?? 0
            ]
        ])
    }

    private func sendJSON(_ object: [String: Any]) async {
        guard let socket,
              let data = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: data, encoding: .utf8) else { return }
        do {
            try await socket.send(.string(text))
        } catch {
            logHandler?(.debug, "Gateway send failed: \(error.localizedDescription)")
        }
    }
}
