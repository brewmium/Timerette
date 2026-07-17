import XCTest
@testable import timerette

final class TimeFormatTests: XCTestCase {
	// The 3.1 format table
	func testCompactTable() {
		XCTAssertEqual(TimeFormat.compact(36), "36s")
		XCTAssertEqual(TimeFormat.compact(5 * 60 + 14), "5m 14s")
		XCTAssertEqual(TimeFormat.compact(2 * 3600 + 3 * 60 + 7), "2h 3m 7s")
		XCTAssertEqual(TimeFormat.compact(4 * 86400 + 3 * 3600 + 3 * 60 + 1), "4d 3h 3m 1s")
		XCTAssertEqual(TimeFormat.compact(180), "3m")
		XCTAssertEqual(TimeFormat.compact(2 * 3600 + 7), "2h 0m 7s")
	}

	func testEndZerosTrimmedInteriorKept() {
		XCTAssertEqual(TimeFormat.compact(3600), "1h")
		XCTAssertEqual(TimeFormat.compact(86400), "1d")
		XCTAssertEqual(TimeFormat.compact(86400 + 60), "1d 0h 1m")
		XCTAssertEqual(TimeFormat.compact(3661), "1h 1m 1s")
		XCTAssertEqual(TimeFormat.compact(3601), "1h 0m 1s")
	}

	func testZeroAndNegative() {
		XCTAssertEqual(TimeFormat.compact(0), "0s")
		XCTAssertEqual(TimeFormat.compact(-5), "0s")
	}

	// Remaining time ceils so a just-started 150s timer reads 2m 30s
	func testCeilOnFractional() {
		XCTAssertEqual(TimeFormat.compact(149.99), "2m 30s")
		XCTAssertEqual(TimeFormat.compact(0.4), "1s")
	}
}
