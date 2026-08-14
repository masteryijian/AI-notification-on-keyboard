import XCTest
@testable import PixiuLED

final class ProtocolTests: XCTestCase {
    private func task(_ id: String, key: Int, status: AgentTaskStatus) -> AgentTask {
        AgentTask(
            sessionID: id,
            key: key,
            status: status,
            cwd: "",
            turnID: "",
            updatedAt: 0
        )
    }

    func testNumberRowColorsLandInSlotsElevenThroughTwenty() {
        let reports = makeColorTableReports([1: .green, 9: .red, 0: .orange])
        XCTAssertEqual(reports.count, 9)

        let table = reports.dropFirst().dropLast().flatMap { report in
            Array(report[8..<(8 + Int(report[4]))])
        }
        XCTAssertEqual(table.count, 378)
        XCTAssertEqual(Array(table[33...35]), [0x00, 0x54, 0x1C])
        XCTAssertEqual(Array(table[57...59]), [0xFF, 0x00, 0x00])
        XCTAssertEqual(Array(table[60...62]), [0xFF, 0x60, 0x00])
    }

    func testOffUsesCapturedCherrySentinel() {
        XCTAssertEqual(LEDColor.off.rgb.0, 0xFF)
        XCTAssertEqual(LEDColor.off.rgb.1, 0xFF)
        XCTAssertEqual(LEDColor.off.rgb.2, 0xFF)
    }

    func testProtocolEnvelope() {
        let reports = makeColorTableReports([1: .orange])
        XCTAssertEqual(reports.first?[0], 0x04)
        XCTAssertEqual(reports.first?[3], 0x01)
        XCTAssertEqual(reports.last?[3], 0x02)
        XCTAssertTrue(reports.dropFirst().dropLast().allSatisfy { $0[3] == 0x0B })
    }

    func testAllocationAssignsZeroAfterNine() {
        var state = AgentTaskState(lastAssignedKey: 9)

        XCTAssertEqual(nextAssignableKey(in: &state), 0)
        XCTAssertEqual(state.lastAssignedKey, 0)
    }

    func testAllocationWrapsAfterZeroAndSkipsRunningKeys() {
        var state = AgentTaskState(
            tasks: [
                "busy-1": task("busy-1", key: 1, status: .running),
                "done-2": task("done-2", key: 2, status: .done),
            ],
            lastAssignedKey: 0
        )

        XCTAssertEqual(nextAssignableKey(in: &state), 2)
        XCTAssertNil(state.tasks["done-2"])
        XCTAssertNotNil(state.tasks["busy-1"])
        XCTAssertEqual(state.lastAssignedKey, 2)
    }

    func testAllocationNeverReplacesTenRunningTasks() {
        let tasks = Dictionary(uniqueKeysWithValues: agentTaskKeys.map { key in
            ("busy-\(key)", task("busy-\(key)", key: key, status: .running))
        })
        var state = AgentTaskState(tasks: tasks, lastAssignedKey: 0)

        XCTAssertNil(nextAssignableKey(in: &state))
        XCTAssertEqual(state.tasks.count, 10)
        XCTAssertEqual(state.lastAssignedKey, 0)
    }
}
