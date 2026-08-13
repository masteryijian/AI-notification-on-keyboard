import XCTest
@testable import PixiuLED

final class ProtocolTests: XCTestCase {
    func testNumberRowColorsLandInSlotsElevenThroughNineteen() {
        let reports = makeColorTableReports([1: .green, 9: .red])
        XCTAssertEqual(reports.count, 9)

        let table = reports.dropFirst().dropLast().flatMap { report in
            Array(report[8..<(8 + Int(report[4]))])
        }
        XCTAssertEqual(table.count, 378)
        XCTAssertEqual(Array(table[33...35]), [0x00, 0x54, 0x1C])
        XCTAssertEqual(Array(table[57...59]), [0xFF, 0x00, 0x00])
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
}
