import Foundation

private struct DesktopTaskEvent {
    let sessionID: String
    let cwd: String
    let turnID: String
    let status: AgentTaskStatus
    let timestamp: TimeInterval
}

private struct ParsedRollout {
    let sessionID: String
    let cwd: String
    let events: [DesktopTaskEvent]
}

private struct RolloutCursor {
    var offset: UInt64
    var remainder = Data()
    var sessionID: String
    var cwd: String
}

/// Watches the append-only rollout records written by Codex Desktop and CLI.
/// Hook events remain enabled as a low-latency fallback; both sources use the
/// same session ID, so duplicate start/finish events update one keyboard slot.
final class DesktopActivityMonitor {
    private let rootURL: URL
    private let fileManager = FileManager.default
    private let recentInterval: TimeInterval
    private let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private var cursors: [String: RolloutCursor] = [:]
    private var bootstrapped = false
    private var lastDiscovery = Date.distantPast

    init(rootURL: URL? = nil, recentInterval: TimeInterval = 36 * 60 * 60) {
        if let rootURL {
            self.rootURL = rootURL
        } else if let override = ProcessInfo.processInfo.environment["PIXIU_CODEX_SESSIONS"],
                  !override.isEmpty {
            self.rootURL = URL(fileURLWithPath: override)
        } else {
            self.rootURL = fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent(".codex/sessions")
        }
        self.recentInterval = recentInterval
    }

    func poll() throws {
        if !bootstrapped {
            try bootstrap()
            bootstrapped = true
            return
        }

        let now = Date()
        if now.timeIntervalSince(lastDiscovery) >= 2.0 {
            try discoverNewFiles(now: now)
            lastDiscovery = now
        }

        for path in Array(cursors.keys) {
            try readAppendedData(path: path)
        }
    }

    private func bootstrap() throws {
        let files = try recentRolloutFiles(now: Date())
        var latestBySession: [String: DesktopTaskEvent] = [:]

        for url in files {
            let data = try Data(contentsOf: url)
            let parsed = parseCompleteFile(data, url: url)
            for event in parsed.events {
                if event.timestamp >= (latestBySession[event.sessionID]?.timestamp ?? 0) {
                    latestBySession[event.sessionID] = event
                }
            }
            cursors[url.path] = RolloutCursor(
                offset: UInt64(data.count),
                sessionID: parsed.sessionID,
                cwd: parsed.cwd
            )
        }

        // At app launch, import only genuinely active work. Historical completed
        // turns must not occupy keys 1-9 merely because their files are recent.
        for event in latestBySession.values {
            // Completed historical sessions update an already assigned slot but
            // never allocate a new one; active sessions are imported immediately.
            try apply(event, createIfMissing: event.status == .running)
        }
        lastDiscovery = Date()
    }

    private func discoverNewFiles(now: Date) throws {
        for url in try recentRolloutFiles(now: now) where cursors[url.path] == nil {
            let data = try Data(contentsOf: url)
            let parsed = parseCompleteFile(data, url: url)
            cursors[url.path] = RolloutCursor(
                offset: UInt64(data.count),
                sessionID: parsed.sessionID,
                cwd: parsed.cwd
            )
            // A file first seen after bootstrap belongs to newly created or newly
            // resumed desktop work, so replay its events in order.
            for event in parsed.events {
                try apply(event, createIfMissing: event.status == .running)
            }
        }
    }

    private func readAppendedData(path: String) throws {
        guard var cursor = cursors[path] else { return }
        let url = URL(fileURLWithPath: path)
        let attributes = try fileManager.attributesOfItem(atPath: path)
        let size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        if size < cursor.offset {
            // A replaced/truncated rollout is treated as a newly discovered file.
            cursors.removeValue(forKey: path)
            return
        }
        guard size > cursor.offset else { return }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: cursor.offset)
        let appended = try handle.readToEnd() ?? Data()
        cursor.offset += UInt64(appended.count)
        cursor.remainder.append(appended)

        let (lines, remainder) = splitCompleteLines(cursor.remainder)
        cursor.remainder = remainder
        for line in lines {
            guard let object = jsonObject(line) else { continue }
            if let metadata = sessionMetadata(object, fallbackURL: url) {
                cursor.sessionID = metadata.id
                cursor.cwd = metadata.cwd
            }
            if let event = taskEvent(object, sessionID: cursor.sessionID, cwd: cursor.cwd) {
                try apply(event, createIfMissing: event.status == .running)
            }
        }
        cursors[path] = cursor
    }

    private func apply(_ event: DesktopTaskEvent, createIfMissing: Bool) throws {
        try updateTask(
            sessionID: event.sessionID,
            status: event.status,
            cwd: event.cwd,
            turnID: event.turnID,
            updatedAt: event.timestamp,
            createIfMissing: createIfMissing
        )
    }

    private func recentRolloutFiles(now: Date) throws -> [URL] {
        guard fileManager.fileExists(atPath: rootURL.path) else { return [] }
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey]
        var result: [URL] = []
        let cutoff = now.addingTimeInterval(-recentInterval)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current

        // Rollouts are partitioned as YYYY/MM/DD. Looking only at the current
        // three day folders keeps discovery cheap even after years of Codex use.
        for daysAgo in 0...2 {
            guard let date = calendar.date(byAdding: .day, value: -daysAgo, to: now) else { continue }
            let components = calendar.dateComponents([.year, .month, .day], from: date)
            guard let year = components.year, let month = components.month, let day = components.day else { continue }
            let directory = rootURL
                .appendingPathComponent(String(format: "%04d", year), isDirectory: true)
                .appendingPathComponent(String(format: "%02d", month), isDirectory: true)
                .appendingPathComponent(String(format: "%02d", day), isDirectory: true)
            let files = (try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles]
            )) ?? []
            for url in files where url.pathExtension == "jsonl" {
                let values = try? url.resourceValues(forKeys: Set(keys))
                guard values?.isRegularFile == true,
                      (values?.contentModificationDate ?? .distantPast) >= cutoff else { continue }
                result.append(url)
            }
        }
        return result
    }

    private func parseCompleteFile(_ data: Data, url: URL) -> ParsedRollout {
        let allLines = [UInt8](data)
            .split(separator: 0x0A, omittingEmptySubsequences: true)
            .map { Data($0) }
        var sessionID = sessionIDFromFilename(url) ?? ""
        var cwd = ""

        // session_meta can be emitted after task_started, so collect metadata first.
        for line in allLines {
            guard let object = jsonObject(line),
                  let metadata = sessionMetadata(object, fallbackURL: url) else { continue }
            sessionID = metadata.id
            if !metadata.cwd.isEmpty { cwd = metadata.cwd }
        }

        guard !sessionID.isEmpty else {
            return ParsedRollout(sessionID: "", cwd: cwd, events: [])
        }
        let events = allLines.compactMap { line -> DesktopTaskEvent? in
            guard let object = jsonObject(line) else { return nil }
            return taskEvent(object, sessionID: sessionID, cwd: cwd)
        }
        return ParsedRollout(sessionID: sessionID, cwd: cwd, events: events)
    }

    private func jsonObject(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private func sessionMetadata(
        _ object: [String: Any],
        fallbackURL: URL
    ) -> (id: String, cwd: String)? {
        guard object["type"] as? String == "session_meta",
              let payload = object["payload"] as? [String: Any] else { return nil }
        let id = payload["id"] as? String ?? sessionIDFromFilename(fallbackURL) ?? ""
        return id.isEmpty ? nil : (id, payload["cwd"] as? String ?? "")
    }

    private func taskEvent(
        _ object: [String: Any],
        sessionID: String,
        cwd: String
    ) -> DesktopTaskEvent? {
        guard !sessionID.isEmpty,
              object["type"] as? String == "event_msg",
              let payload = object["payload"] as? [String: Any],
              let type = payload["type"] as? String else { return nil }

        let status: AgentTaskStatus
        switch type {
        case "task_started":
            status = .running
        case "task_complete", "turn_aborted", "task_cancelled":
            status = .done
        case "stream_error", "task_failed", "turn_failed":
            status = .error
        default:
            return nil
        }

        let timestamp = parseTimestamp(object["timestamp"] as? String)
            ?? Date().timeIntervalSince1970
        return DesktopTaskEvent(
            sessionID: sessionID,
            cwd: cwd,
            turnID: payload["turn_id"] as? String ?? "",
            status: status,
            timestamp: timestamp
        )
    }

    private func parseTimestamp(_ value: String?) -> TimeInterval? {
        guard let value else { return nil }
        return timestampFormatter.date(from: value)?.timeIntervalSince1970
    }

    private func sessionIDFromFilename(_ url: URL) -> String? {
        let base = url.deletingPathExtension().lastPathComponent
        guard base.count >= 36 else { return nil }
        let candidate = String(base.suffix(36))
        return UUID(uuidString: candidate) == nil ? nil : candidate
    }

    private func splitCompleteLines(_ data: Data) -> ([Data], Data) {
        guard let lastNewline = data.lastIndex(of: 0x0A) else { return ([], data) }
        let complete = [UInt8](data[..<lastNewline])
        let remainderStart = data.index(after: lastNewline)
        let lines = complete
            .split(separator: 0x0A, omittingEmptySubsequences: true)
            .map { Data($0) }
        return (lines, Data(data[remainderStart...]))
    }
}
