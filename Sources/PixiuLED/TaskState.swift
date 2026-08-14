import Darwin
import Foundation

/// Physical number-row order: zero follows nine and wraps back to one.
let agentTaskKeys = Array(1...9) + [0]

func agentTaskKeyOrder(_ key: Int) -> Int {
    agentTaskKeys.firstIndex(of: key) ?? agentTaskKeys.count
}

enum AgentTaskStatus: String, Codable {
    case running
    case done
    case error
}

struct AgentTask: Codable {
    var sessionID: String
    var key: Int
    var status: AgentTaskStatus
    var cwd: String
    var turnID: String
    var updatedAt: TimeInterval
}

struct AgentTaskState: Codable {
    var tasks: [String: AgentTask] = [:]
    var lastAssignedKey: Int = 0

    init(tasks: [String: AgentTask] = [:], lastAssignedKey: Int = 0) {
        self.tasks = tasks
        self.lastAssignedKey = lastAssignedKey
    }

    private enum CodingKeys: String, CodingKey {
        case tasks
        case lastAssignedKey
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tasks = try container.decodeIfPresent([String: AgentTask].self, forKey: .tasks) ?? [:]
        // Legacy state files did not store a cursor. Starting after the highest
        // occupied key preserves their existing 1,2,3... allocation naturally.
        lastAssignedKey = try container.decodeIfPresent(Int.self, forKey: .lastAssignedKey)
            ?? tasks.values.map(\.key).max()
            ?? 0
    }
}

private struct DaemonRuntimeState: Codable {
    let pid: Int32
    let phase: String
    let signature: String
    let error: String?
    let updatedAt: TimeInterval
}

private var daemonStatusURL: URL {
    TaskStore.stateURL.deletingLastPathComponent().appendingPathComponent("daemon-status.json")
}

private func writeDaemonStatus(phase: String, signature: String, error: String? = nil) {
    do {
        let state = DaemonRuntimeState(
            pid: ProcessInfo.processInfo.processIdentifier,
            phase: phase,
            signature: signature,
            error: error,
            updatedAt: Date().timeIntervalSince1970
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(state).write(to: daemonStatusURL, options: .atomic)
    } catch {
        fputs("pixiu-led daemon: could not write runtime status (\(error.localizedDescription))\n", stderr)
    }
}

func printDaemonStatus() throws {
    let data = try Data(contentsOf: daemonStatusURL)
    let state = try JSONDecoder().decode(DaemonRuntimeState.self, from: data)
    let date = Date(timeIntervalSince1970: state.updatedAt).formatted(
        .iso8601.year().month().day().time(includingFractionalSeconds: true)
    )
    print("Daemon: pid=\(state.pid) phase=\(state.phase) at=\(date)")
    print("Colors: \(state.signature.isEmpty ? "none" : state.signature)")
    if let error = state.error {
        print("Error: \(error)")
    }
}

final class DaemonInstanceLock {
    private let fileDescriptor: Int32

    private init(fileDescriptor: Int32) {
        self.fileDescriptor = fileDescriptor
    }

    deinit {
        flock(fileDescriptor, LOCK_UN)
        Darwin.close(fileDescriptor)
    }

    static func acquire() throws -> DaemonInstanceLock? {
        let url = TaskStore.stateURL.deletingLastPathComponent().appendingPathComponent("daemon.lock")
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let descriptor = Darwin.open(url.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            let code = errno
            Darwin.close(descriptor)
            if code == EWOULDBLOCK || code == EAGAIN { return nil }
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
        return DaemonInstanceLock(fileDescriptor: descriptor)
    }
}

enum TaskStore {
    static var stateURL: URL {
        if let override = ProcessInfo.processInfo.environment["PIXIU_LED_STATE"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/PixiuAgentLED/state.json")
    }

    static var lockURL: URL {
        stateURL.deletingPathExtension().appendingPathExtension("lock")
    }

    static func read() throws -> AgentTaskState {
        try withLock(write: false) { $0 }
    }

    static func update(_ body: (inout AgentTaskState) throws -> Void) throws {
        try withLock(write: true) { state in
            try body(&state)
        }
    }

    private static func withLock<T>(write: Bool, _ body: (inout AgentTaskState) throws -> T) throws -> T {
        let directory = stateURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let fd = Darwin.open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard fd >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { Darwin.close(fd) }
        guard flock(fd, LOCK_EX) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { flock(fd, LOCK_UN) }

        var state = AgentTaskState()
        if let data = try? Data(contentsOf: stateURL), !data.isEmpty {
            state = try JSONDecoder().decode(AgentTaskState.self, from: data)
        }
        let result = try body(&state)
        if write {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(state).write(to: stateURL, options: .atomic)
        }
        return result
    }
}

func updateTask(
    sessionID: String,
    status: AgentTaskStatus,
    cwd: String,
    turnID: String,
    updatedAt: TimeInterval = Date().timeIntervalSince1970,
    createIfMissing: Bool = false
) throws {
    try TaskStore.update { state in
        if var existing = state.tasks[sessionID] {
            existing.status = status
            if !cwd.isEmpty { existing.cwd = cwd }
            if !turnID.isEmpty { existing.turnID = turnID }
            existing.updatedAt = updatedAt
            state.tasks[sessionID] = existing
            return
        }

        guard createIfMissing else { return }
        guard let key = nextAssignableKey(in: &state) else { return }
        state.tasks[sessionID] = AgentTask(
            sessionID: sessionID,
            key: key,
            status: status,
            cwd: cwd,
            turnID: turnID,
            updatedAt: updatedAt
        )
    }
}

/// Advances around 1...9,0, skipping every key whose task is still running.
/// A free key or the first completed/error key in cyclic order is reusable.
func nextAssignableKey(in state: inout AgentTaskState) -> Int? {
    let normalizedLastKey = agentTaskKeys.contains(state.lastAssignedKey) ? state.lastAssignedKey : 0
    let lastIndex = agentTaskKeys.firstIndex(of: normalizedLastKey) ?? (agentTaskKeys.count - 1)
    for offset in 1...agentTaskKeys.count {
        let candidate = agentTaskKeys[(lastIndex + offset) % agentTaskKeys.count]
        if let occupied = state.tasks.first(where: { $0.value.key == candidate }) {
            guard occupied.value.status != .running else { continue }
            state.tasks.removeValue(forKey: occupied.key)
        }
        state.lastAssignedKey = candidate
        return candidate
    }
    return nil
}

func updateTaskFromHook(_ data: Data) throws {
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let event = object["hook_event_name"] as? String,
          let sessionID = object["session_id"] as? String else {
        throw NSError(domain: "PixiuLED", code: 10, userInfo: [
            NSLocalizedDescriptionKey: "Hook JSON is missing hook_event_name or session_id",
        ])
    }

    let cwd = object["cwd"] as? String ?? ""
    let turnID = object["turn_id"] as? String ?? ""
    let now = Date().timeIntervalSince1970

    if event == "UserPromptSubmit" {
        try updateTask(sessionID: sessionID, status: .running, cwd: cwd, turnID: turnID,
                       updatedAt: now, createIfMissing: true)
    } else if event == "Stop" {
        try updateTask(sessionID: sessionID, status: .done, cwd: cwd, turnID: turnID,
                       updatedAt: now)
    } else if event == "PixiuError" {
        // Reserved for integrations that can report a reliable task failure.
        try updateTask(sessionID: sessionID, status: .error, cwd: cwd, turnID: turnID,
                       updatedAt: now)
    }
}

func printTaskStatus() throws {
    let state = try TaskStore.read()
    if state.tasks.isEmpty {
        print("No assigned agent tasks.")
        return
    }
    for task in state.tasks.values.sorted(by: { agentTaskKeyOrder($0.key) < agentTaskKeyOrder($1.key) }) {
        let folder = task.cwd.isEmpty ? "-" : URL(fileURLWithPath: task.cwd).lastPathComponent
        print("\(task.key): \(task.status.rawValue)  \(folder)  session=\(task.sessionID)")
    }
}

func clearTaskState() throws {
    try TaskStore.update {
        $0.tasks.removeAll()
        $0.lastAssignedKey = 0
    }
}

func taskColors() throws -> [Int: LEDColor] {
    let state = try TaskStore.read()
    return Dictionary(uniqueKeysWithValues: state.tasks.values.map { task in
        let color: LEDColor
        switch task.status {
        case .running:
            color = .orange
        case .done:
            color = .green
        case .error:
            color = .red
        }
        return (task.key, color)
    })
}

func runDaemon() -> Never {
    let desktopMonitor = DesktopActivityMonitor()
    var lastSignature = ""
    var lastError = ""
    var observedSignature = ""
    writeDaemonStatus(phase: "started", signature: "")
    while true {
        autoreleasepool {
            do {
                try desktopMonitor.poll()
                let colors = try taskColors()
                let signature = colors.keys.sorted(by: { agentTaskKeyOrder($0) < agentTaskKeyOrder($1) })
                    .map { "\($0):\(colors[$0]!.rawValue)" }
                    .joined(separator: ",")
                observedSignature = signature
                if signature != lastSignature {
                    writeDaemonStatus(phase: "sending", signature: signature)
                    guard let candidate = try findCandidates().first(where: { $0.isRGBInterface }) else {
                        throw NSError(domain: "PixiuLED", code: 11, userInfo: [
                            NSLocalizedDescriptionKey: "PIXIU 75 RGB interface not found",
                        ])
                    }
                    try sendReports(makeColorTableReports(colors), to: candidate)
                    lastSignature = signature
                    lastError = ""
                    writeDaemonStatus(phase: "applied", signature: signature)
                }
            } catch {
                if error.localizedDescription != lastError {
                    fputs("pixiu-led daemon: \(error.localizedDescription)\n", stderr)
                    lastError = error.localizedDescription
                }
                writeDaemonStatus(
                    phase: "error",
                    signature: observedSignature,
                    error: error.localizedDescription
                )
            }
        }
        Thread.sleep(forTimeInterval: 0.20)
    }
}
