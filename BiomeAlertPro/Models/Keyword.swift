import Foundation

/// The category a keyword belongs to. Biome categories drive rare-biome
/// classification; `action` keywords add supporting confidence.
enum KeywordCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case glitched
    case dreamspace
    case cyberspace
    case singularity
    case action
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .glitched: return "Glitched"
        case .dreamspace: return "Dreamspace"
        case .cyberspace: return "Cyberspace"
        case .singularity: return "Singularity"
        case .action: return "Action Words"
        case .custom: return "Custom"
        }
    }

    /// Whether this category represents a biome (as opposed to a supporting word).
    var isBiome: Bool {
        switch self {
        case .glitched, .dreamspace, .cyberspace, .singularity: return true
        case .action, .custom: return false
        }
    }

    /// Rare biomes trigger the strongest alerts.
    var isRare: Bool {
        switch self {
        case .glitched, .dreamspace: return true
        default: return false
        }
    }

    var symbolName: String {
        switch self {
        case .glitched: return "bolt.trianglebadge.exclamationmark"
        case .dreamspace: return "moon.stars.fill"
        case .cyberspace: return "network"
        case .singularity: return "circle.circle.fill"
        case .action: return "text.magnifyingglass"
        case .custom: return "slider.horizontal.3"
        }
    }
}

/// How a keyword is matched against incoming text.
enum KeywordMatchMode: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Substring match anywhere in the normalized text.
    case partial
    /// Match only against whole tokens (word boundaries).
    case wholeWord
    /// User-supplied regular expression.
    case regex

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .partial: return "Partial"
        case .wholeWord: return "Whole Word"
        case .regex: return "Regex"
        }
    }
}

/// A single user-editable detection keyword.
struct Keyword: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var text: String
    var category: KeywordCategory
    var matchMode: KeywordMatchMode
    var isEnabled: Bool
    /// Contribution to the confidence score, 0...1. Higher = more specific.
    var weight: Double
    /// Whether fuzzy (small-typo) matching may be applied to this keyword.
    var allowsFuzzy: Bool

    init(
        id: UUID = UUID(),
        text: String,
        category: KeywordCategory,
        matchMode: KeywordMatchMode = .partial,
        isEnabled: Bool = true,
        weight: Double = 0.5,
        allowsFuzzy: Bool = false
    ) {
        self.id = id
        self.text = text
        self.category = category
        self.matchMode = matchMode
        self.isEnabled = isEnabled
        self.weight = weight
        self.allowsFuzzy = allowsFuzzy
    }
}

/// The built-in keyword database, matching the Sol's RNG community vocabulary.
enum DefaultKeywords {
    static func all() -> [Keyword] {
        var list: [Keyword] = []

        func add(_ texts: [String], _ category: KeywordCategory, mode: KeywordMatchMode, weight: Double, fuzzy: Bool = false) {
            for text in texts {
                list.append(Keyword(text: text, category: category, matchMode: mode, weight: weight, allowsFuzzy: fuzzy))
            }
        }

        // Glitched — strong, distinctive names get partial matching and high weight;
        // short fragments are whole-word with lower weight to avoid false positives.
        add(["glitched biome", "glitched ps"], .glitched, mode: .partial, weight: 0.95)
        add(["glitched", "glitch"], .glitched, mode: .partial, weight: 0.85, fuzzy: true)
        add(["glit", "gli"], .glitched, mode: .wholeWord, weight: 0.4)

        // Dreamspace
        add(["dreamspace", "dream ps"], .dreamspace, mode: .partial, weight: 0.95, fuzzy: true)
        add(["dream"], .dreamspace, mode: .wholeWord, weight: 0.7)
        add(["drm", "ds"], .dreamspace, mode: .wholeWord, weight: 0.35)

        // Cyberspace
        add(["cyberspace", "cyber ps", "cspace"], .cyberspace, mode: .partial, weight: 0.9, fuzzy: true)
        add(["cyber"], .cyberspace, mode: .wholeWord, weight: 0.65)
        add(["cyb"], .cyberspace, mode: .wholeWord, weight: 0.35)

        // Singularity
        add(["singularity"], .singularity, mode: .partial, weight: 0.9, fuzzy: true)
        add(["sing"], .singularity, mode: .wholeWord, weight: 0.5)
        add(["sng", "sg"], .singularity, mode: .wholeWord, weight: 0.3)

        // Supporting action / context words
        add(["rare biome", "private server", "ps link"], .action, mode: .partial, weight: 0.3)
        add(["biome", "merchant", "hurry", "asap", "teleport", "roblox", "server", "link", "join", "quick"], .action, mode: .wholeWord, weight: 0.15)
        add(["ps", "tp"], .action, mode: .wholeWord, weight: 0.1)

        return list
    }
}
