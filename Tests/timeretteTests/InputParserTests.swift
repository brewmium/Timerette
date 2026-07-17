import XCTest
@testable import timerette

final class InputParserTests: XCTestCase {
	let calendar = Calendar.current

	// A fixed "now": 2026-07-17 14:00:00 local
	var now: Date {
		var comps = DateComponents()
		comps.year = 2026
		comps.month = 7
		comps.day = 17
		comps.hour = 14
		comps.minute = 0
		comps.second = 0
		return calendar.date(from: comps)!
	}

	private func duration(_ input: String) -> TimeInterval? {
		guard case .duration(let span)? = InputParser.parse(input, now: now, calendar: calendar) else { return nil }
		return span
	}

	private func clock(_ input: String) -> Date? {
		guard case .clockTime(let date)? = InputParser.parse(input, now: now, calendar: calendar) else { return nil }
		return date
	}

	private func hourMinute(_ date: Date) -> (Int, Int) {
		let c = calendar.dateComponents([.hour, .minute], from: date)
		return (c.hour!, c.minute!)
	}

	// MARK: The 3.4 examples table -- durations

	func testBareNumberIsMinutes() {
		XCTAssertEqual(duration("2.5"), 150)
		XCTAssertEqual(duration("15"), 900)
	}

	func testTrailingUnitlessNumberIsNextSmallerUnit() {
		XCTAssertEqual(duration("15m45"), 945)
		XCTAssertEqual(duration("2h30"), 9000)
		XCTAssertEqual(duration("3d22"), 3 * 86400 + 22 * 3600)
	}

	func testUnitNumbers() {
		XCTAssertEqual(duration("90s"), 90)
		XCTAssertEqual(duration("2d"), 172800)
		XCTAssertEqual(duration("3d22h"), 3 * 86400 + 22 * 3600)
		XCTAssertEqual(duration("1.5h"), 5400)
		XCTAssertEqual(duration("45m"), 2700)
	}

	func testMultiComponentWithSpaces() {
		XCTAssertEqual(duration("1h30m"), 5400)
		XCTAssertEqual(duration("2h 30m"), 9000)
		XCTAssertEqual(duration("1d 2h 3m 4s"), 86400 + 7200 + 180 + 4)
	}

	func testCaseInsensitive() {
		XCTAssertEqual(duration("2H30M"), 9000)
		XCTAssertEqual(duration(" 90S "), 90)
	}

	func testMaxClamp() {
		XCTAssertEqual(duration("500d"), InputParser.maxDuration)
	}

	// MARK: The 3.4 examples table -- clock times

	func testTwentyFourHourColon() {
		XCTAssertEqual(hourMinute(clock("15:00")!).0, 15)
		XCTAssertEqual(hourMinute(clock("15:00")!).1, 0)
		XCTAssertEqual(hourMinute(clock("9:30")!).0, 9)
		XCTAssertEqual(hourMinute(clock("9:30")!).1, 30)
	}

	func testMeridiem() {
		XCTAssertEqual(hourMinute(clock("3:30pm")!).0, 15)
		XCTAssertEqual(hourMinute(clock("3:30pm")!).1, 30)
		XCTAssertEqual(hourMinute(clock("3:30p")!).0, 15)
		XCTAssertEqual(hourMinute(clock("3pm")!).0, 15)
		XCTAssertEqual(hourMinute(clock("3p")!).0, 15)
		XCTAssertEqual(hourMinute(clock("3p")!).1, 0)
		XCTAssertEqual(hourMinute(clock("9am")!).0, 9)
		XCTAssertEqual(hourMinute(clock("9a")!).0, 9)
	}

	func testNoonAndMidnight() {
		XCTAssertEqual(hourMinute(clock("12a")!).0, 0)
		XCTAssertEqual(hourMinute(clock("12p")!).0, 12)
	}

	// now is 14:00 -- 15:00 is later today, 9:30 already passed so tomorrow
	func testNextOccurrenceResolution() {
		let laterToday = clock("15:00")!
		XCTAssertEqual(laterToday.timeIntervalSince(now), 3600, accuracy: 1)

		let tomorrow = clock("9:30")!
		XCTAssertGreaterThan(tomorrow, now)
		XCTAssertEqual(calendar.dateComponents([.day], from: now, to: tomorrow).day, 0)
		XCTAssertEqual(tomorrow.timeIntervalSince(now), (24 - 14 + 9) * 3600 + 1800, accuracy: 3700)
	}

	func testAlwaysResolvesToFuture() {
		for input in ["15:00", "9:30", "3p", "12a", "12p", "2:00"] {
			let date = clock(input)!
			XCTAssertGreaterThan(date, now, "\(input) resolved to the past")
			XCTAssertLessThanOrEqual(date.timeIntervalSince(now), 86400 + 3700, "\(input) more than a day out")
		}
	}

	// MARK: Bare number is NOT a clock time

	func testBareThreeIsThreeMinutes() {
		XCTAssertEqual(duration("3"), 180)
		XCTAssertNil(clock("3"))
	}

	// MARK: Nil cases

	func testNilCases() {
		XCTAssertNil(InputParser.parse("", now: now, calendar: calendar))
		XCTAssertNil(InputParser.parse("   ", now: now, calendar: calendar))
		XCTAssertNil(InputParser.parse("abc", now: now, calendar: calendar))
		XCTAssertNil(InputParser.parse("0", now: now, calendar: calendar))
		XCTAssertNil(InputParser.parse("0m", now: now, calendar: calendar))
		XCTAssertNil(InputParser.parse("15 45", now: now, calendar: calendar))
		XCTAssertNil(InputParser.parse("90s30", now: now, calendar: calendar))
		XCTAssertNil(InputParser.parse("2x", now: now, calendar: calendar))
		XCTAssertNil(InputParser.parse("..", now: now, calendar: calendar))
		XCTAssertNil(InputParser.parse("25:00", now: now, calendar: calendar))
		XCTAssertNil(InputParser.parse("13pm", now: now, calendar: calendar))
		XCTAssertNil(InputParser.parse("3:5", now: now, calendar: calendar))
		XCTAssertNil(InputParser.parse("3:75", now: now, calendar: calendar))
		XCTAssertNil(InputParser.parse("pm", now: now, calendar: calendar))
	}

	// MARK: Inline labels

	func testInlineLabels() {
		let tea = InputParser.parseWithLabel("2.5 tea", now: now, calendar: calendar)
		XCTAssertEqual(tea?.input, .duration(150))
		XCTAssertEqual(tea?.label, "tea")

		let pasta = InputParser.parseWithLabel("2h 30m pasta sauce", now: now, calendar: calendar)
		XCTAssertEqual(pasta?.input, .duration(9000))
		XCTAssertEqual(pasta?.label, "pasta sauce")

		let standup = InputParser.parseWithLabel("3:30pm standup", now: now, calendar: calendar)
		XCTAssertEqual(standup?.label, "standup")
		if case .clockTime(let date)? = standup?.input {
			XCTAssertEqual(hourMinute(date).0, 15)
			XCTAssertEqual(hourMinute(date).1, 30)
		} else {
			XCTFail("3:30pm standup should be a clock time")
		}

		let plain = InputParser.parseWithLabel("2.5", now: now, calendar: calendar)
		XCTAssertEqual(plain?.input, .duration(150))
		XCTAssertNil(plain?.label)
	}

	func testInlineLabelRejections() {
		// Two bare numbers stay rejected -- "45" is not a label
		XCTAssertNil(InputParser.parseWithLabel("15 45", now: now, calendar: calendar))
		XCTAssertNil(InputParser.parseWithLabel("tea", now: now, calendar: calendar))
		XCTAssertNil(InputParser.parseWithLabel("tea time", now: now, calendar: calendar))
	}

	// MARK: Preview titles

	func testPreviewTitles() {
		let d = InputParser.parse("2.5", now: now, calendar: calendar)!
		XCTAssertEqual(d.previewTitle(now: now), "Start a 2m 30s timer")

		let multi = InputParser.parse("3d22h", now: now, calendar: calendar)!
		XCTAssertEqual(multi.previewTitle(now: now), "Start a 3d 22h timer")

		let alarm = InputParser.parse("3p", now: now, calendar: calendar)!
		guard case .clockTime(let date) = alarm else { return XCTFail("3p not a clock time") }
		let expected = "Alarm at \(TimeFormat.clockString(date))  (in \(TimeFormat.compact(date.timeIntervalSince(now))))"
		XCTAssertEqual(alarm.previewTitle(now: now), expected)
		XCTAssertTrue(alarm.previewTitle(now: now).hasPrefix("Alarm at 3:00"))
	}
}
