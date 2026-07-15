import Foundation
import SwiftUI

/// Severity level for structured logging.
enum LogLevel: String, Codable, CaseIterable, Identifiable, Comparable, Sendable {
    case debug
    case info
    case warning
    case error

    var id: String { rawValue }

    private var rank: Int {
        switch self {
        case .debug: return 0
        case .info: return 1
        case .warning: return 2
        case .error: return 3
        }
    }

    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool { lhs.rank < rhs.rank }

    var displayName: String { rawValue.capitalized }

    var symbolName: String {
        switch self {
        case .debug: return "ant"
        case .info: return "info.circle"
        case .warning: return "exclamationmark.triangle"
        case .error: return "xmark.octagon"
        }
    }

    var tint: Color {
        switch self {
        case .debug: return .secondary
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        }
    }
}

/// Functional area a log line belongs to.
enum LogCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case lifecycle
    case network
    case webhook
    case detection
    case launch
    case performance
    case security

    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

/// A single structured log entry.
struct LogEntry: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let date: Date
    let level: LogLevel
    let category: LogCategory
    let message: String

    init(id: UUID = UUID(), date: Date = Date(), level: LogLevel, category: LogCategory, message: String) {
        self.id = id
        self.date = date
        self.level = level
        self.category = category
        self.message = message
    }
}
