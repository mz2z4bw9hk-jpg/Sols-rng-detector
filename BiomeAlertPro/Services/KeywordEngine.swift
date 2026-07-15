import Foundation

/// A single keyword hit within a message.
struct KeywordMatch: Hashable, Sendable {
    let keyword: Keyword
    let matchedText: String
    let isFuzzy: Bool
}

/// Aggregated detection outcome for one message.
struct DetectionResult: Sendable {
    let matches: [KeywordMatch]
    /// Highest-weighted biome category that matched, if any.
    let biomeCategory: KeywordCategory?
    /// 0...1 confidence from keywords alone (link bonus is applied later).
    let confidence: Double

    var matchedKeywordTexts: [String] {
        var seen = Set<String>()
        return matches.compactMap { match in
            seen.insert(match.keyword.text).inserted ? match.keyword.text : nil
        }
    }

    static let empty = DetectionResult(matches: [], biomeCategory: nil, confidence: 0)
}

/// Abstraction for testability / dependency injection.
protocol KeywordMatching: Sendable {
    func detect(in text: String, keywords: [Keyword], fuzzyEnabled: Bool) -> DetectionResult
}

/// Pure, allocation-light keyword matcher.
///
/// Pipeline per message:
/// 1. Unicode + case + diacritic normalization.
/// 2. Tokenization for whole-word and fuzzy matching.
/// 3. Per-keyword matching in its configured mode (partial / whole word / regex),
///    with optional Levenshtein-distance-1 fuzzy fallback for typo tolerance.
/// 4. Confidence scoring: strongest biome keyword + diminishing support from
///    action words.
struct KeywordEngine: KeywordMatching {

    func detect(in text: String, keywords: [Keyword], fuzzyEnabled: Bool) -> DetectionResult {
        let normalized = Self.normalize(text)
        guard !normalized.isEmpty else { return .empty }
        let tokens = Self.tokenize(normalized)

        var matches: [KeywordMatch] = []

        for keyword in keywords where keyword.isEnabled {
            let needle = Self.normalize(keyword.text)
            guard !needle.isEmpty else { continue }

            switch keyword.matchMode {
            case .partial:
                if normalized.contains(needle) {
                    matches.append(KeywordMatch(keyword: keyword, matchedText: keyword.text, isFuzzy: false))
                    continue
                }
            case .wholeWord:
                if needle.contains(" ") {
                    // Multi-word "whole word" keywords fall back to phrase search.
                    if normalized.contains(needle) {
                        matches.append(KeywordMatch(keyword: keyword, matchedText: keyword.text, isFuzzy: false))
                        continue
                    }
                } else if tokens.contains(needle) {
                    matches.append(KeywordMatch(keyword: keyword, matchedText: keyword.text, isFuzzy: false))
                    continue
                }
            case .regex:
                if let regex = try? Regex(keyword.text).ignoresCase(),
                   text.firstMatch(of: regex) != nil {
                    matches.append(KeywordMatch(keyword: keyword, matchedText: keyword.text, isFuzzy: false))
                }
                continue
            }

            // Fuzzy fallback: tolerate one typo on sufficiently long keywords.
            if fuzzyEnabled, keyword.allowsFuzzy, needle.count >= 5, !needle.contains(" ") {
                if let hit = tokens.first(where: { Self.isWithinEditDistanceOne($0, needle) }) {
                    matches.append(KeywordMatch(keyword: keyword, matchedText: hit, isFuzzy: true))
                }
            }
        }

        guard !matches.isEmpty else { return .empty }

        // Confidence: strongest biome signal + diminishing support words.
        var biomeCategory: KeywordCategory?
        var biomeScore = 0.0
        var supportScore = 0.0
        var supportCount = 0

        for match in matches {
            let effectiveWeight = match.isFuzzy ? match.keyword.weight * 0.7 : match.keyword.weight
            if match.keyword.category.isBiome {
                if effectiveWeight > biomeScore {
                    biomeScore = effectiveWeight
                    biomeCategory = match.keyword.category
                }
            } else if supportCount < 3 {
                supportScore += effectiveWeight
                supportCount += 1
            }
        }

        let confidence = min(1.0, biomeScore + supportScore)
        return DetectionResult(matches: matches, biomeCategory: biomeCategory, confidence: confidence)
    }

    // MARK: - Normalization

    /// Lowercases, strips diacritics, and normalizes width/Unicode forms so
    /// "Glítchéd" and "ＧＬＩＴＣＨ" both match "glitched".
    static func normalize(_ text: String) -> String {
        text.precomposedStringWithCanonicalMapping
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .lowercased()
    }

    static func tokenize(_ normalized: String) -> Set<String> {
        var tokens = Set<String>()
        var current = ""
        for character in normalized {
            if character.isLetter || character.isNumber {
                current.append(character)
            } else if !current.isEmpty {
                tokens.insert(current)
                current = ""
            }
        }
        if !current.isEmpty { tokens.insert(current) }
        return tokens
    }

    // MARK: - Fuzzy matching

    /// Bounded Levenshtein check: true when edit distance <= 1.
    static func isWithinEditDistanceOne(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        let aChars = Array(a)
        let bChars = Array(b)
        let lenDiff = aChars.count - bChars.count
        if abs(lenDiff) > 1 { return false }

        var i = 0
        var j = 0
        var edits = 0
        while i < aChars.count && j < bChars.count {
            if aChars[i] == bChars[j] {
                i += 1
                j += 1
                continue
            }
            edits += 1
            if edits > 1 { return false }
            if lenDiff == 0 {
                i += 1; j += 1        // substitution
            } else if lenDiff > 0 {
                i += 1                // deletion from a
            } else {
                j += 1                // insertion into a
            }
        }
        edits += (aChars.count - i) + (bChars.count - j)
        return edits <= 1
    }
}
