import Foundation
import Network

/// Listener lifecycle state, published to the UI.
enum ListenerState: Sendable, Equatable {
    case stopped
    case starting
    case listening(port: UInt16)
    case failed(String)

    var displayName: String {
        switch self {
        case .stopped: return "Stopped"
        case .starting: return "Starting…"
        case .listening(let port): return "Listening on port \(port)"
        case .failed(let message): return "Failed: \(message)"
        }
    }

    var isActive: Bool {
        if case .listening = self { return true }
        return false
    }
}

/// A tiny, hardened HTTP/1.1 endpoint that receives webhook-style alert
/// payloads from the user's own forwarders (e.g. a Discord bot they run, or
/// any tool that can POST JSON). Binds to loopback by default; payloads are
/// size-capped and may require a shared secret header.
///
/// Accepted bodies (POST, any path):
/// - Discord "Execute Webhook" JSON (`content`, `username`, `embeds`)
/// - `{"message": "..."}`
/// - Raw UTF-8 text
final class WebhookListenerService: @unchecked Sendable {
    /// Header clients must send when a shared secret is configured.
    static let secretHeader = "x-biomealert-secret"
    private static let maxBodyBytes = 1_048_576 // 1 MB

    let events: AsyncStream<IncomingEvent>
    private let eventContinuation: AsyncStream<IncomingEvent>.Continuation

    /// State callback; may be invoked on the listener queue.
    var onState: (@Sendable (ListenerState) -> Void)?
    /// Lightweight log hook; may be invoked on the listener queue.
    var onLog: (@Sendable (LogLevel, String) -> Void)?

    private let queue = DispatchQueue(label: "com.biomealert.BiomeAlertPro.listener")
    private var listener: NWListener?
    private var connections: [Int: NWConnection] = [:]
    private var nextConnectionID = 0
    private var sharedSecret: String?

    init() {
        (events, eventContinuation) = AsyncStream.makeStream(of: IncomingEvent.self)
    }

    func start(port: UInt16, sharedSecret: String?, allowLAN: Bool) {
        queue.async { [self] in
            stopLocked()
            self.sharedSecret = (sharedSecret?.isEmpty == false) ? sharedSecret : nil
            onState?(.starting)

            do {
                guard let nwPort = NWEndpoint.Port(rawValue: port) else {
                    onState?(.failed("Invalid port \(port)"))
                    return
                }
                let parameters = NWParameters.tcp
                parameters.allowLocalEndpointReuse = true
                if !allowLAN {
                    parameters.requiredLocalEndpoint = NWEndpoint.hostPort(
                        host: NWEndpoint.Host("127.0.0.1"),
                        port: nwPort
                    )
                }
                let newListener = allowLAN
                    ? try NWListener(using: parameters, on: nwPort)
                    : try NWListener(using: parameters)

                newListener.stateUpdateHandler = { [weak self] state in
                    guard let self else { return }
                    switch state {
                    case .ready:
                        self.onState?(.listening(port: port))
                        self.onLog?(.info, "Webhook listener ready on \(allowLAN ? "0.0.0.0" : "127.0.0.1"):\(port)")
                    case .failed(let error):
                        self.onState?(.failed(error.localizedDescription))
                        self.onLog?(.error, "Webhook listener failed: \(error.localizedDescription)")
                    case .cancelled:
                        self.onState?(.stopped)
                    default:
                        break
                    }
                }
                newListener.newConnectionHandler = { [weak self] connection in
                    self?.queue.async {
                        self?.accept(connection)
                    }
                }
                newListener.start(queue: queue)
                listener = newListener
            } catch {
                onState?(.failed(error.localizedDescription))
                onLog?(.error, "Could not start webhook listener: \(error.localizedDescription)")
            }
        }
    }

    func stop() {
        queue.async { [self] in
            stopLocked()
            onState?(.stopped)
        }
    }

    // MARK: - Connection handling (always on `queue`)

    private func stopLocked() {
        listener?.cancel()
        listener = nil
        for (_, connection) in connections {
            connection.cancel()
        }
        connections.removeAll()
    }

    private func accept(_ connection: NWConnection) {
        nextConnectionID += 1
        let id = nextConnectionID
        connections[id] = connection

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                self?.queue.async { self?.connections.removeValue(forKey: id) }
            default:
                break
            }
        }
        connection.start(queue: queue)
        receive(on: connection, id: id, buffer: Data())
    }

    private func receive(on connection: NWConnection, id: Int, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }

            if buffer.count > Self.maxBodyBytes * 2 {
                self.respond(connection, id: id, status: 413, body: #"{"error":"payload too large"}"#)
                return
            }
            if error != nil {
                self.close(connection, id: id)
                return
            }

            if let request = HTTPRequest(raw: buffer) {
                if request.isComplete {
                    self.handle(request, connection: connection, id: id)
                    return
                }
                if let expected = request.contentLength, expected > Self.maxBodyBytes {
                    self.respond(connection, id: id, status: 413, body: #"{"error":"payload too large"}"#)
                    return
                }
            }

            if isComplete {
                self.close(connection, id: id)
                return
            }
            self.receive(on: connection, id: id, buffer: buffer)
        }
    }

    private func handle(_ request: HTTPRequest, connection: NWConnection, id: Int) {
        switch request.method {
        case "GET":
            respond(connection, id: id, status: 200,
                    body: #"{"app":"Biome Alert Pro","status":"listening"}"#)

        case "POST":
            if let secret = sharedSecret {
                let provided = request.headers[Self.secretHeader] ?? ""
                guard Self.constantTimeEquals(provided, secret) else {
                    onLog?(.warning, "Rejected webhook POST: bad or missing shared secret")
                    respond(connection, id: id, status: 401, body: #"{"error":"unauthorized"}"#)
                    return
                }
            }
            guard let event = Self.parseEvent(from: request.body) else {
                onLog?(.warning, "Rejected webhook POST: empty or unparseable payload")
                respond(connection, id: id, status: 400, body: #"{"error":"invalid payload"}"#)
                return
            }
            eventContinuation.yield(event)
            respond(connection, id: id, status: 200, body: #"{"status":"accepted"}"#)

        default:
            respond(connection, id: id, status: 405, body: #"{"error":"method not allowed"}"#)
        }
    }

    /// Parses a request body into a normalized event. Returns nil when no
    /// usable text can be extracted (invalid payload / missing fields).
    static func parseEvent(from body: Data) -> IncomingEvent? {
        guard !body.isEmpty else { return nil }
        let decoder = JSONDecoder()

        if let payload = try? decoder.decode(DiscordWebhookPayload.self, from: body) {
            let content = payload.content ?? ""
            let embedText = payload.embedText
            if !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !embedText.isEmpty {
                return IncomingEvent(
                    id: payload.id,
                    source: .webhookListener,
                    sender: payload.username,
                    content: content,
                    embedText: embedText
                )
            }
        }
        if let simple = try? decoder.decode(SimpleMessagePayload.self, from: body),
           !simple.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return IncomingEvent(source: .webhookListener, content: simple.message)
        }
        if let text = String(data: body, encoding: .utf8),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !text.hasPrefix("{") {
            return IncomingEvent(source: .webhookListener, content: text)
        }
        return nil
    }

    private func respond(_ connection: NWConnection, id: Int, status: Int, body: String) {
        let reason: String
        switch status {
        case 200: reason = "OK"
        case 400: reason = "Bad Request"
        case 401: reason = "Unauthorized"
        case 405: reason = "Method Not Allowed"
        case 413: reason = "Payload Too Large"
        default: reason = "Error"
        }
        let bodyData = Data(body.utf8)
        let head = "HTTP/1.1 \(status) \(reason)\r\n" +
            "Content-Type: application/json\r\n" +
            "Content-Length: \(bodyData.count)\r\n" +
            "Connection: close\r\n\r\n"
        var response = Data(head.utf8)
        response.append(bodyData)
        connection.send(content: response, completion: .contentProcessed { [weak self] _ in
            self?.queue.async { self?.close(connection, id: id) }
        })
    }

    private func close(_ connection: NWConnection, id: Int) {
        connection.cancel()
        connections.removeValue(forKey: id)
    }

    /// Timing-safe string comparison for the shared secret.
    static func constantTimeEquals(_ a: String, _ b: String) -> Bool {
        let aBytes = Array(a.utf8)
        let bBytes = Array(b.utf8)
        guard aBytes.count == bBytes.count else { return false }
        var difference: UInt8 = 0
        for index in 0..<aBytes.count {
            difference |= aBytes[index] ^ bBytes[index]
        }
        return difference == 0
    }
}

/// Minimal HTTP/1.1 request parser (headers + Content-Length body).
private struct HTTPRequest {
    let method: String
    let path: String
    let headers: [String: String]
    let contentLength: Int?
    let body: Data
    let isComplete: Bool

    init?(raw: Data) {
        guard let headerEnd = raw.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        guard let headerText = String(data: raw[..<headerEnd.lowerBound], encoding: .utf8) else { return nil }

        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        method = String(parts[0]).uppercased()
        path = String(parts[1])

        var parsedHeaders: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            parsedHeaders[key] = value
        }
        headers = parsedHeaders
        contentLength = parsedHeaders["content-length"].flatMap { Int($0) }

        let bodyData = raw[headerEnd.upperBound...]
        let expected = contentLength ?? 0
        body = Data(bodyData.prefix(expected))
        isComplete = bodyData.count >= expected
    }
}
