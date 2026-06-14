import Foundation

/// Real `CostProviding`: prices the **current** Claude Code session by reading
/// the single newest-mtime transcript under `~/.claude/projects` and summing
/// each assistant message's token usage at the per-model rate.
///
/// "Current session" = the most recently modified `.jsonl`, which is the one
/// Claude Code is actively appending to. This deliberately tracks one session's
/// running spend rather than a daily total.
///
/// Robustness: any failure (missing directory, unreadable file, malformed line)
/// is non-fatal. A missing/empty transcript yields the last good value, never a
/// crash and never a blank gauge.
final class TranscriptCostProvider: CostProviding {
    private let projectsDirectory: URL
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
         excludedPathFragments: [String] = ["observer-sessions"]) {
        self.projectsDirectory = projectsDirectory
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".claude/projects", isDirectory: true)
        self.excludedPathFragments = excludedPathFragments
    }

    func currentSessionCost() -> Double {
        guard let transcript = newestTranscript(),
              let cost = cost(ofTranscriptAt: transcript) else {
            return lastGoodCost
        }
        lastGoodCost = cost
        return cost
    }

    /// The most recently modified `.jsonl` anywhere under the projects tree.
    private func newestTranscript() -> URL? {
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
        return newest?.url
    }

    /// Sum the priced usage of every assistant line in one transcript.
    /// Returns nil only if the file can't be read at all; bad individual lines
    /// are skipped.
    private func cost(ofTranscriptAt url: URL) -> Double? {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        var total = 0.0
        contents.enumerateLines { line, _ in
            total += Self.cost(ofLine: line)
        }
        return total
    }

    /// Price one transcript line. Non-assistant or unparseable lines cost $0.
    private static func cost(ofLine line: String) -> Double {
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

    /// Tolerant int read: handles Int, Double, and numeric strings; else 0.
    private static func int(_ value: Any?) -> Int {
        switch value {
        case let n as Int: return n
        case let d as Double: return Int(d)
        case let s as String: return Int(s) ?? 0
        default: return 0
        }
    }
}
