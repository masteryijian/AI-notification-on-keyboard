import AppKit
import Foundation
import IOKit.hid

enum PixiuProtocol {
    static let vendorID = 0x046A
    static let productID = 0x01E2
    static let reportLength = 64
    static let reportID = 4
    static let colorTableLength = 378
    static let numberRowFirstSlot = 11
}

enum LEDColor: String {
    case off
    case red
    case orange
    case green

    var rgb: (UInt8, UInt8, UInt8) {
        switch self {
        case .off:
            // CHERRY Utility uses FF FF FF as its disabled/no-colour sentinel.
            return (0xFF, 0xFF, 0xFF)
        case .red:
            return (0xFF, 0x00, 0x00)
        case .orange:
            // Warm amber/orange used while an agent is working.
            return (0xFF, 0x60, 0x00)
        case .green:
            return (0x00, 0x54, 0x1C)
        }
    }
}

struct HIDCandidate {
    let device: IOHIDDevice
    let usagePage: Int
    let usage: Int
    let maxInput: Int
    let maxOutput: Int
    let maxFeature: Int
    let reportDescriptor: Data

    var outputReportIDs: Set<Int> {
        parseOutputReportIDs(reportDescriptor)
    }

    var isRGBInterface: Bool {
        maxOutput == PixiuProtocol.reportLength && outputReportIDs.contains(PixiuProtocol.reportID)
    }
}

func intProperty(_ device: IOHIDDevice, _ key: String) -> Int {
    guard let value = IOHIDDeviceGetProperty(device, key as CFString) else { return 0 }
    return (value as? NSNumber)?.intValue ?? 0
}

func stringProperty(_ device: IOHIDDevice, _ key: String) -> String {
    guard let value = IOHIDDeviceGetProperty(device, key as CFString) else { return "" }
    return value as? String ?? ""
}

func dataProperty(_ device: IOHIDDevice, _ key: String) -> Data {
    guard let value = IOHIDDeviceGetProperty(device, key as CFString) else { return Data() }
    return value as? Data ?? Data()
}

func parseOutputReportIDs(_ descriptor: Data) -> Set<Int> {
    let bytes = [UInt8](descriptor)
    var index = 0
    var currentReportID = 0
    var outputIDs = Set<Int>()

    while index < bytes.count {
        let prefix = bytes[index]
        index += 1
        if prefix == 0xFE {
            guard index + 1 < bytes.count else { break }
            let size = Int(bytes[index])
            index += 2 + size
            continue
        }

        let sizeCode = Int(prefix & 0x03)
        let size = sizeCode == 3 ? 4 : sizeCode
        let itemType = (prefix >> 2) & 0x03
        let tag = (prefix >> 4) & 0x0F
        guard index + size <= bytes.count else { break }

        if itemType == 1 && tag == 8 && size >= 1 {
            currentReportID = Int(bytes[index])
        } else if itemType == 0 && tag == 9 {
            outputIDs.insert(currentReportID)
        }
        index += size
    }
    return outputIDs
}

func findCandidates() throws -> [HIDCandidate] {
    let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    let matching: [String: Any] = [
        kIOHIDVendorIDKey as String: PixiuProtocol.vendorID,
        kIOHIDProductIDKey as String: PixiuProtocol.productID,
    ]
    IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)

    let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    guard openResult == kIOReturnSuccess else {
        throw NSError(domain: "PixiuLED", code: Int(openResult), userInfo: [
            NSLocalizedDescriptionKey: String(format: "IOHIDManagerOpen failed: 0x%08X", openResult),
        ])
    }

    guard let set = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return [] }
    return set.map { device in
        HIDCandidate(
            device: device,
            usagePage: intProperty(device, kIOHIDPrimaryUsagePageKey),
            usage: intProperty(device, kIOHIDPrimaryUsageKey),
            maxInput: intProperty(device, kIOHIDMaxInputReportSizeKey),
            maxOutput: intProperty(device, kIOHIDMaxOutputReportSizeKey),
            maxFeature: intProperty(device, kIOHIDMaxFeatureReportSizeKey),
            reportDescriptor: dataProperty(device, kIOHIDReportDescriptorKey)
        )
    }.sorted { ($0.usagePage, $0.usage) < ($1.usagePage, $1.usage) }
}

func makeReport(command: UInt8, rgb: (UInt8, UInt8, UInt8)? = nil) -> [UInt8] {
    var report = [UInt8](repeating: 0, count: PixiuProtocol.reportLength)
    report[0] = 0x04
    report[3] = command
    report[7] = 0x55

    if let rgb {
        report[4] = 0x08
        report[5] = 0x01
        report[8] = 0x08
        report[9] = 0x04
        report[10] = 0x02
        report[11] = 0x01
        report[13] = rgb.0
        report[14] = rgb.1
        report[15] = rgb.2
    }
    return report
}

func makeColorTableReports(_ colors: [Int: LEDColor]) -> [[UInt8]] {
    var table = [UInt8](repeating: 0xFF, count: PixiuProtocol.colorTableLength)
    for (key, color) in colors {
        guard let keyIndex = agentTaskKeys.firstIndex(of: key) else { continue }
        let offset = (PixiuProtocol.numberRowFirstSlot + keyIndex) * 3
        let rgb = color.rgb
        table[offset] = rgb.0
        table[offset + 1] = rgb.1
        table[offset + 2] = rgb.2
    }

    var reports = [makeReport(command: 0x01)]
    var offset = 0
    while offset < table.count {
        let chunkLength = min(56, table.count - offset)
        var report = makeReport(command: 0x0B)
        report[4] = UInt8(chunkLength)
        report[5] = UInt8(offset & 0xFF)
        report[6] = UInt8((offset >> 8) & 0xFF)
        report.replaceSubrange(8..<(8 + chunkLength), with: table[offset..<(offset + chunkLength)])
        reports.append(report)
        offset += chunkLength
    }
    reports.append(makeReport(command: 0x02))
    return reports
}

func sendReports(_ reports: [[UInt8]], to candidate: HIDCandidate) throws {
    let openResult = IOHIDDeviceOpen(candidate.device, IOOptionBits(kIOHIDOptionsTypeNone))
    guard openResult == kIOReturnSuccess else {
        throw NSError(domain: "PixiuLED", code: Int(openResult), userInfo: [
            NSLocalizedDescriptionKey: String(format: "Could not open RGB interface: 0x%08X", openResult),
        ])
    }
    defer { IOHIDDeviceClose(candidate.device, IOOptionBits(kIOHIDOptionsTypeNone)) }

    for (index, report) in reports.enumerated() {
        let result = report.withUnsafeBytes { rawBuffer -> IOReturn in
            guard let baseAddress = rawBuffer.baseAddress else { return kIOReturnBadArgument }
            return IOHIDDeviceSetReport(
                candidate.device,
                kIOHIDReportTypeOutput,
                CFIndex(PixiuProtocol.reportID),
                baseAddress.assumingMemoryBound(to: UInt8.self),
                report.count
            )
        }
        guard result == kIOReturnSuccess else {
            throw NSError(domain: "PixiuLED", code: Int(result), userInfo: [
                NSLocalizedDescriptionKey: String(format: "Report %d failed: 0x%08X", index + 1, result),
            ])
        }
        Thread.sleep(forTimeInterval: 0.025)
    }
}

func hex(_ bytes: [UInt8]) -> String {
    bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
}

func printUsage() {
    print("""
    Usage:
      pixiu-led list
      pixiu-led probe
      pixiu-led key1 <off|red|orange|green> [--apply]
      pixiu-led set <0-9> <off|red|orange|green> [...] [--apply]
      pixiu-led hook                 # reads Codex hook JSON from stdin
      pixiu-led daemon
      pixiu-led desktop-sync          # import active Codex Desktop tasks once
      pixiu-led desktop-watch <secs>  # diagnostic monitor without keyboard output
      pixiu-led open-task <0-9>       # open the task assigned to a number key
      pixiu-led hotkeys               # show registered shortcut conflicts
      pixiu-led daemon-status         # show the last keyboard update from the monitor
      pixiu-led status
      pixiu-led clear

    Without --apply, the command is a dry run and sends nothing.
    """)
}

do {
    let arguments = Array(CommandLine.arguments.dropFirst())
    if arguments.isEmpty, Bundle.main.bundleURL.pathExtension == "app" {
        guard let instanceLock = try DaemonInstanceLock.acquire() else {
            exit(0)
        }
        let application = NSApplication.shared
        application.setActivationPolicy(.prohibited)
        application.finishLaunching()
        if IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) != kIOHIDAccessTypeGranted {
            _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        }
        let hotKeyNavigator = HotKeyNavigator()
        _ = hotKeyNavigator.start()
        Thread.detachNewThread {
            runDaemon()
        }
        withExtendedLifetime((hotKeyNavigator, instanceLock)) {
            application.run()
        }
    }
    guard let command = arguments.first else {
        printUsage()
        exit(2)
    }

    if command == "hook" {
        try updateTaskFromHook(FileHandle.standardInput.readDataToEndOfFile())
        print("{\"continue\":true}")
        exit(0)
    }

    if command == "status" {
        try printTaskStatus()
        exit(0)
    }

    if command == "desktop-sync" {
        let monitor = DesktopActivityMonitor()
        try monitor.poll()
        try printTaskStatus()
        exit(0)
    }

    if command == "desktop-watch", arguments.count == 2,
       let seconds = Double(arguments[1]), seconds > 0 {
        let monitor = DesktopActivityMonitor()
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            try monitor.poll()
            Thread.sleep(forTimeInterval: 0.20)
        }
        try printTaskStatus()
        exit(0)
    }

    if command == "open-task", arguments.count == 2,
       let key = Int(arguments[1]), agentTaskKeys.contains(key) {
        try openTaskForKey(key)
        print("Opened the Codex task assigned to key \(key).")
        exit(0)
    }

    if command == "hotkeys" {
        try printHotKeyStatus()
        exit(0)
    }

    if command == "daemon-status" {
        try printDaemonStatus()
        exit(0)
    }

    if command == "clear" {
        try clearTaskState()
        print("Cleared all task assignments.")
        exit(0)
    }

    if command == "daemon" {
        guard let instanceLock = try DaemonInstanceLock.acquire() else {
            print("Pixiu Agent LED is already running.")
            exit(0)
        }
        withExtendedLifetime(instanceLock) {
            runDaemon()
        }
    }

    let candidates = try findCandidates()
    if command == "list" {
        if candidates.isEmpty {
            print("No PIXIU 75 found (VID 046A, PID 01E2).")
            exit(1)
        }
        for (index, candidate) in candidates.enumerated() {
            let product = stringProperty(candidate.device, kIOHIDProductKey)
            let reportIDs = candidate.outputReportIDs.sorted().map(String.init).joined(separator: ",")
            let marker = candidate.isRGBInterface ? "  <-- RGB protocol candidate" : ""
            print(String(format: "[%d] %@ usagePage=0x%04X usage=0x%04X input=%d output=%d feature=%d outputIDs={%@}%@",
                         index, product, candidate.usagePage, candidate.usage,
                         candidate.maxInput, candidate.maxOutput, candidate.maxFeature, reportIDs, marker))
        }
        exit(0)
    }

    if command == "probe" {
        guard let candidate = candidates.first(where: { $0.isRGBInterface }) else {
            fputs("PIXIU 75 RGB interface with output Report ID 4 was not found.\n", stderr)
            exit(1)
        }
        let result = IOHIDDeviceOpen(candidate.device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else {
            fputs(String(format: "Could not open RGB interface: 0x%08X\n", result), stderr)
            exit(1)
        }
        IOHIDDeviceClose(candidate.device, IOOptionBits(kIOHIDOptionsTypeNone))
        print("Probe succeeded: RGB interface opened and closed; no report was sent.")
        exit(0)
    }

    guard let candidate = candidates.first(where: { $0.isRGBInterface }) else {
        fputs("PIXIU 75 RGB interface with output Report ID 4 was not found.\n", stderr)
        exit(1)
    }

    if command == "set" {
        let values = arguments.dropFirst().filter { $0 != "--apply" }
        guard !values.isEmpty, values.count.isMultiple(of: 2) else {
            printUsage()
            exit(2)
        }
        var colors: [Int: LEDColor] = [:]
        var index = values.startIndex
        while index < values.endIndex {
            let colorIndex = values.index(after: index)
            guard let key = Int(values[index]), agentTaskKeys.contains(key),
                  let color = LEDColor(rawValue: values[colorIndex]) else {
                printUsage()
                exit(2)
            }
            colors[key] = color
            index = values.index(colorIndex, offsetBy: 1)
        }

        let reports = makeColorTableReports(colors)
        let summary = colors.keys.sorted().map { "\($0)=\(colors[$0]!.rawValue)" }.joined(separator: ", ")
        print("Validated number-row color table: \(summary); \(reports.count) reports")
        guard arguments.contains("--apply") else {
            print("Dry run only: no data was sent to the keyboard.")
            exit(0)
        }
        try sendReports(reports, to: candidate)
        print("Applied number-row color table successfully.")
        exit(0)
    }

    guard command == "key1", arguments.count >= 2, let color = LEDColor(rawValue: arguments[1]) else {
        printUsage()
        exit(2)
    }

    let reports = [
        makeReport(command: 0x01),
        makeReport(command: 0x06, rgb: color.rgb),
        makeReport(command: 0x02),
    ]

    print("Matched PIXIU 75 RGB interface: output=64, Report ID=4")
    print("Captured protocol reports for key 1 / \(color.rawValue):")
    for (index, report) in reports.enumerated() {
        print("  [\(index + 1)] \(hex(report))")
    }

    guard arguments.contains("--apply") else {
        print("Dry run only: no data was sent to the keyboard.")
        exit(0)
    }

    try sendReports(reports, to: candidate)
    print("Applied key 1 / \(color.rawValue) successfully.")
} catch {
    fputs("Error: \(error.localizedDescription)\n", stderr)
    exit(1)
}
