import Foundation

/// Real `CostProviding`: reports the running cost of the Claude Code session the
/// user is currently working in.
///
/// **Active session** = the single newest-mtime `.jsonl` under `~/.claude/projects`.
/// That is the transcript Claude Code is actively appending to, i.e. the session
/// the user most recently interacted with ("the one I last clicked into"). The
/// `.jsonl` filename stem is the session id.
///
/// **Cost** = the official figure Claude Code already computes. It writes one
/// line per request to `~/.claude/metrics/costs.jsonl` with a cumulative
/// `estimated_cost_usd` per `session_id` — the same number the cost-warning hook
/// reports. We surface that directly rather than re-deriving cost from token
/// counts, which previously came out ~2-3× too low (the `costUSD` field inside
/// the transcript itself is null, so it cannot be read there).
///
/// `costs.jsonl` lags the transcript slightly: a freshly opened session can be
/// the newest `.jsonl` before its first cost line lands. In that window we fall
/// back to pricing the transcript's own token usage so the gauge still tracks
/// *that* session, then snap to the official number as soon as it appears.
///
/// Robustness: every failure (missing directory, unreadable file, malformed
/// line) is non-fatal. A missing/empty source yields the last good value, never
/// a crash and never a blank gauge.
final class TranscriptCostProvider: CostProviding {
    private let projectsDirectory: URL
    private let metricsCostsFile: URL
    /// Path substrings that mark a transcript as background tooling rather than
    /// a real interactive session. The claude-mem observer writes near-empty
    /// `.jsonl` files every few seconds; without this filter "newest mtime"
    /// would constantly snap to a ~$0.01 observer session instead of the
    /// session the user is actually working in.
    private let excludedPathFragments: [String]
    /// Retained so a transient read failure shows the last real number rather
    /// than dropping to $0.
    private var lastGoodCost: Double = 0

    init(projectsDirectory: URL? = nil,
         metricsCostsFile: URL? = nil,
         excludedPathFragments: [String] = ["observer-sessions"]) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.projectsDirectory = projectsDirectory
            ?? home.appendingPathComponent(".claude/projects", isDirectory: true)
        self.metricsCostsFile = metricsCostsFile
            ?? home.appendingPathComponent(".claude/metrics/costs.jsonl", isDirectory: false)
        self.excludedPathFragments = excludedPathFragments
    }

    func currentSessionCost() -> Double {
        guard let active = newestTranscript() else { return lastGoodCost }

        // Prefer the official cumulative cost for this exact session.
        if let official = officialCost(forSessionID: active.sessionID) {
            lastGoodCost = official
            return official
        }

        // No official line yet (session just opened, or costs.jsonl lagging):
        // price this session's own transcript tokens so we still show *this*
        // session rather than jumping elsewhere.
        if let approximate = tokenCost(ofTranscriptAt: active.url) {
            lastGoodCost = approximate
            return approximate
        }

        return lastGoodCost
    }

    /// The most recently modified `.jsonl` anywhere under the projects tree,
    /// paired with its session id (the filename stem).
    private func newestTranscript() -> (url: URL, sessionID: String)? {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: projectsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        var newest: (url: URL, modified: Date)?
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            if excludedPathFragments.contains(where: url.path.contains) { continue }
            let values = try? url.resourceValues(
                forKeys: [.contentModificationDateKey, .isRegularFileKey])
            guard values?.isRegularFile == true,
                  let modified = values?.contentModificationDate else { continue }
            if newest == nil || modified > newest!.modified {
                newest = (url, modified)
            }
        }
        guard let url = newest?.url else { return nil }
        return (url, url.deletingPathExtension().lastPathComponent)
    }

    // MARK: - Official cost (source of truth)

    /// How many trailing bytes of `costs.jsonl` to scan. The file is append-only
    /// and grows for the lifetime of the install, but the latest line for any
    /// session is a few hundred bytes, so reading only the tail keeps this O(1)
    /// per poll tick regardless of total file size.
    private static let costsTailByteBudget: UInt64 = 256 * 1024

    /// Latest cumulative `estimated_cost_usd` for one session id, read from
    /// `~/.claude/metrics/costs.jsonl`. Returns nil when the file is unreadable
    /// or has no line for that session yet.
    ///
    /// The file appends one line per request; the cost is cumulative within a
    /// session, so the last matching line is the current total. Only the tail is
    /// read, and lines are scanned newest-first so the search stops at the first
    /// hit.
    private func officialCost(forSessionID sessionID: String) -> Double? {
        guard let tail = readTail(of: metricsCostsFile, maxBytes: Self.costsTailByteBudget) else {
            return nil
        }

        for line in tail.split(separator: "\n", omittingEmptySubsequences: true).reversed() {
            let line = String(line)
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data),
                  let root = object as? [String: Any],
                  root["session_id"] as? String == sessionID,
                  let cost = Self.double(root["estimated_cost_usd"]) else { continue }
            return cost
        }
        return nil
    }

    // MARK: - Token-priced fallback

    /// Sum the priced token usage of every assistant line in one transcript.
    /// Used only until the session's official cost line appears. Returns nil only
    /// if the file can't be read at all; bad individual lines are skipped.
    private func tokenCost(ofTranscriptAt url: URL) -> Double? {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        var total = 0.0
        contents.enumerateLines { line, _ in
            total += Self.tokenCost(ofLine: line)
        }
        return total
    }

    /// Price one transcript line by token usage. Non-assistant or unparseable
    /// lines cost $0.
    private static func tokenCost(ofLine line: String) -> Double {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let root = object as? [String: Any],
              let message = root["message"] as? [String: Any],
              let model = message["model"] as? String,
              let usageDict = message["usage"] as? [String: Any] else {
            return 0
        }
        return ModelPricing.cost(model: model, usage: usage(from: usageDict))
    }

    /// Map a raw `message.usage` dict into the pricing model's `Usage`.
    private static func usage(from dict: [String: Any]) -> ModelPricing.Usage {
        var usage = ModelPricing.Usage()
        usage.inputTokens = int(dict["input_tokens"])
        usage.outputTokens = int(dict["output_tokens"])
        usage.cacheRead = int(dict["cache_read_input_tokens"])

        if let creation = dict["cache_creation"] as? [String: Any] {
            usage.cacheWrite5m = int(creation["ephemeral_5m_input_tokens"])
            usage.cacheWrite1h = int(creation["ephemeral_1h_input_tokens"])
        } else {
            // Older transcripts only have the flat field; treat it as 5m.
            usage.cacheWrite5m = int(dict["cache_creation_input_tokens"])
        }
        return usage
    }

    // MARK: - Tail reading

    /// Read up to the last `maxBytes` of a file as UTF-8. Returns nil if the file
    /// can't be opened. The first line in the window may be truncated when the
    /// file is larger than the budget; callers tolerate that because a partial
    /// line fails JSON parsing and is skipped.
    private func readTail(of url: URL, maxBytes: UInt64) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let offset = size > maxBytes ? size - maxBytes : 0
        guard (try? handle.seek(toOffset: offset)) != nil,
              let data = try? handle.readToEnd() else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Tolerant numeric parsing

    /// Tolerant int read: handles Int, Double, and numeric strings; else 0.
    private static func int(_ value: Any?) -> Int {
        switch value {
        case let n as Int: return n
        case let d as Double: return Int(d)
        case let s as String: return Int(s) ?? 0
        default: return 0
        }
    }

    /// Tolerant double read: handles Double, Int, and numeric strings; else nil.
    private static func double(_ value: Any?) -> Double? {
        switch value {
        case let d as Double: return d
        case let n as Int: return Double(n)
        case let s as String: return Double(s)
        default: return nil
        }
    }
}
