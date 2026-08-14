import AppKit
import Carbon.HIToolbox
import Foundation

private let pixiuHotKeySignature: OSType = 0x50584C44 // "PXLD"
private let pixiuHotKeyModifiers = UInt32(cmdKey | controlKey)

private let numberKeyCodes: [Int: UInt32] = [
    1: UInt32(kVK_ANSI_1),
    2: UInt32(kVK_ANSI_2),
    3: UInt32(kVK_ANSI_3),
    4: UInt32(kVK_ANSI_4),
    5: UInt32(kVK_ANSI_5),
    6: UInt32(kVK_ANSI_6),
    7: UInt32(kVK_ANSI_7),
    8: UInt32(kVK_ANSI_8),
    9: UInt32(kVK_ANSI_9),
    0: UInt32(kVK_ANSI_0),
]

private struct HotKeyRegistrationState: Codable {
    var shortcut: String
    var registeredKeys: [Int]
    var failures: [String: Int32]
    var updatedAt: TimeInterval
    var lastTriggeredKey: Int?
    var lastTriggeredAt: TimeInterval?
    var lastSessionID: String?
    var lastOutcome: String?
}

private var hotKeyStatusURL: URL {
    TaskStore.stateURL.deletingLastPathComponent().appendingPathComponent("hotkeys.json")
}

private let pixiuHotKeyHandler: EventHandlerUPP = { _, event, userData in
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr, hotKeyID.signature == pixiuHotKeySignature else {
        return OSStatus(eventNotHandledErr)
    }

    let navigator = Unmanaged<HotKeyNavigator>.fromOpaque(userData).takeUnretainedValue()
    navigator.openTask(key: Int(hotKeyID.id))
    return noErr
}

/// Registers ⌃⌘1 … ⌃⌘9 and ⌃⌘0 without intercepting ordinary number-key input.
/// Carbon hot-key registration fails instead of overriding an existing owner.
final class HotKeyNavigator {
    private var hotKeys: [EventHotKeyRef] = []
    private var eventHandler: EventHandlerRef?

    deinit {
        for hotKey in hotKeys {
            UnregisterEventHotKey(hotKey)
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }

    @discardableResult
    func start() -> [Int: OSStatus] {
        if eventHandler == nil {
            var eventType = EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            )
            let context = Unmanaged.passUnretained(self).toOpaque()
            let status = InstallEventHandler(
                GetApplicationEventTarget(),
                pixiuHotKeyHandler,
                1,
                &eventType,
                context,
                &eventHandler
            )
            guard status == noErr else {
                fputs("pixiu-led hotkeys: event handler failed (\(status))\n", stderr)
                writeHotKeyStatus(registered: [], failures: [-1: status])
                return [-1: status]
            }
        }

        var failures: [Int: OSStatus] = [:]
        var registered: [Int] = []
        for key in agentTaskKeys {
            guard let keyCode = numberKeyCodes[key] else { continue }
            var reference: EventHotKeyRef?
            let identifier = EventHotKeyID(signature: pixiuHotKeySignature, id: UInt32(key))
            let status = RegisterEventHotKey(
                keyCode,
                pixiuHotKeyModifiers,
                identifier,
                GetApplicationEventTarget(),
                0,
                &reference
            )
            if status == noErr, let reference {
                hotKeys.append(reference)
                registered.append(key)
            } else {
                failures[key] = status
                fputs("pixiu-led hotkeys: ⌃⌘\(key) unavailable (\(status))\n", stderr)
            }
        }
        writeHotKeyStatus(registered: registered, failures: failures)
        return failures
    }

    func openTask(key: Int) {
        updateHotKeyTrigger(key: key, sessionID: nil, outcome: "received")
        do {
            guard let task = try TaskStore.read().tasks.values.first(where: { $0.key == key }) else {
                updateHotKeyTrigger(key: key, sessionID: nil, outcome: "no-task-assigned")
                NSSound.beep()
                return
            }
            guard let url = URL(string: "codex://threads/\(task.sessionID)") else {
                updateHotKeyTrigger(key: key, sessionID: task.sessionID, outcome: "invalid-url")
                NSSound.beep()
                return
            }
            DispatchQueue.main.async {
                let opened = NSWorkspace.shared.open(url)
                updateHotKeyTrigger(
                    key: key,
                    sessionID: task.sessionID,
                    outcome: opened ? "opened" : "open-failed"
                )
                if opened {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        NSRunningApplication
                            .runningApplications(withBundleIdentifier: "com.openai.codex")
                            .first?
                            .activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
                    }
                } else {
                    NSSound.beep()
                }
            }
        } catch {
            updateHotKeyTrigger(key: key, sessionID: nil, outcome: "state-read-failed")
            fputs("pixiu-led hotkeys: \(error.localizedDescription)\n", stderr)
            NSSound.beep()
        }
    }
}

private func writeHotKeyStatus(registered: [Int], failures: [Int: OSStatus]) {
    do {
        let state = HotKeyRegistrationState(
            shortcut: "Control+Command+1…9,0",
            registeredKeys: registered.sorted(by: { agentTaskKeyOrder($0) < agentTaskKeyOrder($1) }),
            failures: Dictionary(uniqueKeysWithValues: failures.map { (String($0.key), Int32($0.value)) }),
            updatedAt: Date().timeIntervalSince1970,
            lastTriggeredKey: nil,
            lastTriggeredAt: nil,
            lastSessionID: nil,
            lastOutcome: nil
        )
        try FileManager.default.createDirectory(
            at: hotKeyStatusURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(state).write(to: hotKeyStatusURL, options: .atomic)
    } catch {
        fputs("pixiu-led hotkeys: could not write status (\(error.localizedDescription))\n", stderr)
    }
}

private func updateHotKeyTrigger(key: Int, sessionID: String?, outcome: String) {
    do {
        let data = try Data(contentsOf: hotKeyStatusURL)
        var state = try JSONDecoder().decode(HotKeyRegistrationState.self, from: data)
        state.lastTriggeredKey = key
        state.lastTriggeredAt = Date().timeIntervalSince1970
        state.lastSessionID = sessionID
        state.lastOutcome = outcome
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(state).write(to: hotKeyStatusURL, options: .atomic)
    } catch {
        fputs("pixiu-led hotkeys: could not record trigger (\(error.localizedDescription))\n", stderr)
    }
}

func printHotKeyStatus() throws {
    let data = try Data(contentsOf: hotKeyStatusURL)
    let state = try JSONDecoder().decode(HotKeyRegistrationState.self, from: data)
    print("Shortcut: \(state.shortcut)")
    print("Registered keys: \(state.registeredKeys.map(String.init).joined(separator: ","))")
    if state.failures.isEmpty {
        print("Conflicts: none")
    } else {
        let details = state.failures.keys.sorted().map { "\($0)=\(state.failures[$0]!)" }.joined(separator: ", ")
        print("Conflicts: \(details)")
    }
    if let key = state.lastTriggeredKey,
       let timestamp = state.lastTriggeredAt,
       let outcome = state.lastOutcome {
        let date = Date(timeIntervalSince1970: timestamp).formatted(
            .iso8601.year().month().day().time(includingFractionalSeconds: true)
        )
        let session = state.lastSessionID.map { " session=\($0)" } ?? ""
        print("Last trigger: key=\(key) outcome=\(outcome) at=\(date)\(session)")
    } else {
        print("Last trigger: none since app launch")
    }
}

func openTaskForKey(_ key: Int) throws {
    guard let task = try TaskStore.read().tasks.values.first(where: { $0.key == key }) else {
        throw NSError(domain: "PixiuLED", code: 20, userInfo: [
            NSLocalizedDescriptionKey: "No task is assigned to number key \(key)",
        ])
    }
    guard let url = URL(string: "codex://threads/\(task.sessionID)"),
          NSWorkspace.shared.open(url) else {
        throw NSError(domain: "PixiuLED", code: 21, userInfo: [
            NSLocalizedDescriptionKey: "Codex could not open task \(task.sessionID)",
        ])
    }
}
