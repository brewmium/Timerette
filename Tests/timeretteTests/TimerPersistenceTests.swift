import XCTest
@testable import timerette

final class TimerPersistenceTests: XCTestCase {
	private var dir: URL!

	override func setUp() {
		dir = FileManager.default.temporaryDirectory
			.appendingPathComponent("timerette-tests-\(UUID().uuidString)")
		try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
	}

	override func tearDown() {
		try? FileManager.default.removeItem(at: dir)
	}

	private func writeTimersFile(_ timers: [CountdownTimer]) {
		let encoder = JSONEncoder()
		encoder.dateEncodingStrategy = .iso8601
		let data = try! encoder.encode(timers)
		try! data.write(to: dir.appendingPathComponent("timers.json"))
	}

	private func makeTimer(fireIn: TimeInterval, state: TimerState,
		remainingWhenPaused: TimeInterval? = nil, label: String? = nil) -> CountdownTimer
	{
		CountdownTimer(id: UUID(), label: label, kind: .durationTimer, total: 60,
			fireDate: Date().addingTimeInterval(fireIn), state: state,
			remainingWhenPaused: remainingWhenPaused)
	}

	func testStartSurvivesRelaunchFromCorrectFireDate() {
		let store = TimerStore(directory: dir)
		store.start(.duration(300), label: "Tea")
		let fireDate = store.timers[0].fireDate

		let relaunched = TimerStore(directory: dir)
		XCTAssertEqual(relaunched.count, 1)
		XCTAssertEqual(relaunched.timers[0].label, "Tea")
		XCTAssertEqual(relaunched.timers[0].state, .running)
		// ISO8601 rounds to whole seconds
		XCTAssertEqual(relaunched.timers[0].fireDate.timeIntervalSince(fireDate), 0, accuracy: 1)
	}

	func testExpiredTimersDropSilentlyOnRestore() {
		writeTimersFile([
			makeTimer(fireIn: -30, state: .running, label: "expired"),
			makeTimer(fireIn: 500, state: .running, label: "future"),
		])

		var fired: [String] = []
		let store = TimerStore(directory: dir)
		store.onFire = { fired.append($0.displayName) }

		XCTAssertEqual(store.timers.map { $0.label }, ["future"])
		store.tick()
		XCTAssertTrue(fired.isEmpty, "an expired timer must not chime retroactively")
	}

	func testRingingAtQuitDropsOnRestore() {
		writeTimersFile([makeTimer(fireIn: -3, state: .ringing)])
		XCTAssertEqual(TimerStore(directory: dir).count, 0)
	}

	func testPausedTimersRestorePaused() {
		writeTimersFile([makeTimer(fireIn: -100, state: .paused, remainingWhenPaused: 42)])

		let store = TimerStore(directory: dir)
		XCTAssertEqual(store.count, 1)
		XCTAssertEqual(store.timers[0].state, .paused)
		XCTAssertEqual(store.timers[0].remaining, 42)
	}

	func testClockAlarmSurvivesWithAbsoluteTarget() {
		let target = Date().addingTimeInterval(7200)
		let store = TimerStore(directory: dir)
		store.start(.clockTime(target))

		let relaunched = TimerStore(directory: dir)
		XCTAssertEqual(relaunched.timers[0].kind, .clockAlarm)
		XCTAssertEqual(relaunched.timers[0].fireDate.timeIntervalSince(target), 0, accuracy: 1)
	}

	func testCancelPersists() {
		let store = TimerStore(directory: dir)
		store.start(.duration(300))
		store.cancel(id: store.timers[0].id)

		XCTAssertEqual(TimerStore(directory: dir).count, 0)
	}

	func testPruneIsPersistedAtRestore() {
		writeTimersFile([makeTimer(fireIn: -30, state: .running)])
		_ = TimerStore(directory: dir)

		// The pruned list was written back; a corrupt-free reload agrees
		XCTAssertEqual(TimerStore(directory: dir).count, 0)
	}
}
