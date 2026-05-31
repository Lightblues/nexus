import Foundation

/// Substring-first, subsequence fallback scoring. Field weights:
///   title (1.0) > group (0.7) > keywords (0.5) > subtitle (0.3)
/// Empty query returns the input unchanged.
@MainActor
enum PaletteSearch {
    /// Filter + sort `commands` by relevance to `query`. Stable wrt insertion order
    /// when scores tie. Returns full command list when query is empty/whitespace.
    static func score(_ commands: [Command], query: String) -> [Command] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return commands }
        struct Scored {
            let cmd: Command
            let score: Double
            let order: Int
        }
        var scored: [Scored] = []
        for (i, cmd) in commands.enumerated() {
            let s = total(cmd: cmd, needle: needle)
            if s > 0 { scored.append(Scored(cmd: cmd, score: s, order: i)) }
        }
        return scored
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.order < rhs.order
            }
            .map(\.cmd)
    }

    private static func total(cmd: Command, needle: String) -> Double {
        let titleScore    = field(cmd.title.lowercased(), needle: needle) * 1.0
        let groupScore    = (cmd.group?.lowercased()).map { field($0, needle: needle) * 0.7 } ?? 0
        let keywordScore  = cmd.keywords
            .map { field($0.lowercased(), needle: needle) * 0.5 }
            .max() ?? 0
        let subtitleScore = (cmd.subtitle()?.lowercased()).map { field($0, needle: needle) * 0.3 } ?? 0
        return titleScore + groupScore + keywordScore + subtitleScore
    }

    nonisolated private static func field(_ haystack: String, needle: String) -> Double {
        if haystack.contains(needle) {
            // Prefix match boosts beyond mid-string match.
            return haystack.hasPrefix(needle) ? 1.2 : 1.0
        }
        // Subsequence: every char of needle appears in order
        var hi = haystack.startIndex
        let hEnd = haystack.endIndex
        var matched = 0
        for ch in needle {
            guard hi < hEnd else { return 0 }
            if let found = haystack[hi..<hEnd].firstIndex(of: ch) {
                matched += 1
                hi = haystack.index(after: found)
            } else {
                return 0
            }
        }
        // Reward density: short haystack means the needle is a bigger fraction
        let density = Double(matched) / Double(haystack.count)
        return 0.3 + density * 0.3
    }
}
