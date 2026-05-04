/// Fuzzy match scoring utility.
public enum Fuzzy {
    /// Returns a match score (higher is better), or nil if `query` doesn't match `target`.
    ///
    /// Scores bonus points for word-start matches, prefix matches, and consecutive runs.
    public static func score(query: String, target: String) -> Int? {
        let q = Array(query), t = Array(target)
        guard !t.isEmpty else { return nil }

        var wordStart = [Bool](repeating: false, count: t.count)
        wordStart[0] = true
        for i in 1..<t.count where !t[i - 1].isLetter && !t[i - 1].isNumber {
            wordStart[i] = true
        }

        var score = 0, ti = 0, prev = -1, first = -1

        for qc in q {
            // Prefer consecutive match to keep runs together
            if prev >= 0 {
                let next = prev + 1
                if next < t.count && t[next] == qc {
                    score += 7
                    if wordStart[next] { score += 10 }
                    if next == 0 { score += 8 }
                    prev = next; ti = next + 1; continue
                }
            }
            // Then word-start match, then any match
            var ws: Int?, any: Int?
            for j in ti..<t.count where t[j] == qc {
                if any == nil { any = j }
                if wordStart[j] { ws = j; break }
            }
            guard let idx = ws ?? any else { return nil }
            if wordStart[idx] { score += 10 }
            if idx == 0 { score += 8 }
            if first < 0 { first = idx }
            prev = idx; ti = idx + 1
        }

        score -= first // earlier first match wins
        return score
    }
}
