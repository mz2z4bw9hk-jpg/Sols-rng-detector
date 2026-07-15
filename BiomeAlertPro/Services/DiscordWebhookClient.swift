import Foundation

enum WebhookError: LocalizedError {
    case invalidURL
    case httpStatus(Int, String)
    case rateLimited(retryAfter: Double)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "That doesn't look like a valid Discord webhook URL."
        case .httpStatus(let code, let detail):
            return "Discord returned HTTP \(code)\(detail.isEmpty ? "" : ": \(detail)")"
        case .rateLimited(let retryAfter):
            return String(format: "Rate limited by Discord — retry after %.1fs", retryAfter)
        case .network(let message):
            return "Network error: \(message)"
        }
    }
}

/// Abstraction for testability / dependency injection.
protocol WebhookSending: Sendable {
    func fetchInfo(urlString: String) async throws -> DiscordWebhookInfo
    func send(content: String, urlString: String) async throws
}

/// Sends messages to Discord via official *incoming webhook* URLs
/// (`POST /api/webhooks/{id}/{token}`), with validation, retries, and
/// exponential backoff that honors Discord's rate-limit headers.
actor DiscordWebhookClient: WebhookSending {
    private let session: URLSession
    private let maxAttempts: Int

    init(maxAttempts: Int = 4) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 60
        configuration.waitsForConnectivity = false
        self.session = URLSession(configuration: configuration)
        self.maxAttempts = maxAttempts
    }

    /// Strict structural validation of a Discord webhook URL.
    static func isValidWebhookURL(_ string: String) -> Bool {
        let pattern = #/^https://(?:ptb\.|canary\.)?discord(?:app)?\.com/api/webhooks/\d{10,25}/[A-Za-z0-9_-]{30,}$/#
        return string.wholeMatch(of: pattern) != nil
    }

    /// GETs the webhook object — proves the URL is live without posting anything.
    func fetchInfo(urlString: String) async throws -> DiscordWebhookInfo {
        guard Self.isValidWebhookURL(urlString), let url = URL(string: urlString) else {
            throw WebhookError.invalidURL
        }
        let (data, response) = try await perform(URLRequest(url: url))
        guard response.statusCode == 200 else {
            throw WebhookError.httpStatus(response.statusCode, Self.snippet(data))
        }
        return try JSONDecoder().decode(DiscordWebhookInfo.self, from: data)
    }

    /// Posts a message, retrying transient failures with exponential backoff.
    func send(content: String, urlString: String) async throws {
        guard Self.isValidWebhookURL(urlString), let url = URL(string: urlString) else {
            throw WebhookError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = ["content": String(content.prefix(1_900))]
        request.httpBody = try JSONEncoder().encode(body)

        var lastError: Error = WebhookError.network("unknown")
        for attempt in 0..<maxAttempts {
            if attempt > 0 {
                let backoff = min(pow(2.0, Double(attempt)), 30) + Double.random(in: 0...0.5)
                try await Task.sleep(for: .seconds(backoff))
            }
            do {
                let (data, response) = try await perform(request)
                switch response.statusCode {
                case 200...299:
                    return
                case 429:
                    let retryAfter = Self.retryAfter(from: response, data: data)
                    lastError = WebhookError.rateLimited(retryAfter: retryAfter)
                    try await Task.sleep(for: .seconds(min(retryAfter, 30)))
                case 500...599:
                    lastError = WebhookError.httpStatus(response.statusCode, Self.snippet(data))
                default:
                    // Client errors (bad token, deleted webhook) won't improve with retries.
                    throw WebhookError.httpStatus(response.statusCode, Self.snippet(data))
                }
            } catch let error as WebhookError {
                switch error {
                case .rateLimited, .network:
                    lastError = error
                default:
                    throw error
                }
            } catch {
                lastError = WebhookError.network(error.localizedDescription)
            }
        }
        throw lastError
    }

    // MARK: - Helpers

    private func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw WebhookError.network("Non-HTTP response")
            }
            return (data, http)
        } catch let error as WebhookError {
            throw error
        } catch {
            throw WebhookError.network(error.localizedDescription)
        }
    }

    private static func retryAfter(from response: HTTPURLResponse, data: Data) -> Double {
        if let header = response.value(forHTTPHeaderField: "Retry-After"), let seconds = Double(header) {
            return seconds
        }
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let seconds = json["retry_after"] as? Double {
            return seconds
        }
        return 2.0
    }

    private static func snippet(_ data: Data) -> String {
        guard let text = String(data: data, encoding: .utf8) else { return "" }
        return String(text.prefix(200))
    }
}
