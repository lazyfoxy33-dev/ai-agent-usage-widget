import Foundation

/// Which provider the collapsed Touch Bar cell should glance at.
///
/// The collapsed cell answers "what is the coding tool in front of me doing", so
/// it deliberately never consults the Touch Bar selection: it prefers the
/// frontmost coding tool, then the most recently used one, and finally the
/// most-drained window (preferring fresh figures over stale ones).
enum TrayGlance {
    struct Window: Equatable {
        var usedPct: Double
        var stale: Bool
    }

    /// One quota provider's live windows.
    struct Candidate: Equatable {
        var tag: String
        var fiveH: Window?
        var weekly: Window?

        var windows: [Window] { [fiveH, weekly].compactMap { $0 } }
    }

    struct Pick: Equatable {
        var tag: String
        var usedPct: Double
        var stale: Bool
    }

    static func pick(candidates: [Candidate], foreground: String?, lastUsed: String?) -> Pick? {
        if let tag = foreground ?? lastUsed, let pick = tightest(in: candidates, tag: tag) {
            return pick
        }
        return mostDrained(candidates)
    }

    /// Most-drained window of one provider; fresh figures win over stale ones.
    static func tightest(in candidates: [Candidate], tag: String) -> Pick? {
        guard let windows = candidates.first(where: { $0.tag == tag })?.windows,
              !windows.isEmpty else {
            return nil
        }
        let fresh = windows.filter { !$0.stale }
        guard let window = (fresh.isEmpty ? windows : fresh)
            .max(by: { $0.usedPct < $1.usedPct }) else {
            return nil
        }
        return Pick(tag: tag, usedPct: window.usedPct, stale: window.stale)
    }

    /// Most-drained window across every candidate, preferring non-stale figures.
    static func mostDrained(_ candidates: [Candidate]) -> Pick? {
        let all = candidates.flatMap { candidate in
            candidate.windows.map { (candidate.tag, $0) }
        }
        let fresh = all.filter { !$0.1.stale }
        guard let best = (fresh.isEmpty ? all : fresh)
            .max(by: { $0.1.usedPct < $1.1.usedPct }) else {
            return nil
        }
        return Pick(tag: best.0, usedPct: best.1.usedPct, stale: best.1.stale)
    }
}
