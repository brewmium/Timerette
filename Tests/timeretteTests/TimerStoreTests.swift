import XCTest
@testable import timerette

final class TimerStoreTests: XCTestCase {
	private var dir: URL!

	override func setUp() {
		dir = FileManager.default.temporaryDirectory
			.appendingPathComponent("timerette-tests-\(UUID().uuidString)")
		try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
	}

	override func tearDown() {
		try? FileManager.default.removeItem(at: dir)
	}

	private func makeStore() -> TimerStore {
		TimerStore(directory: dir)
	}

	func testStartDurationSetsFireDate() {
		let store = makeStore()
		store.start(.duration(150))
		XCTAssertEqual(store.count, 1)
		let t = store.timers[0]
		XCTAssertEqual(t.kind, .durationTimer)
		XCTAssertEqual(t.state, .running)
		XCTAssertEqual(t.total, 150)
		XCTAssertEqual(t.fireDate.timeIntervalSinceNow, 150, accuracy: 1)
	}

	func testStartClockAlarmKeepsResolvedDate() {
		let store = makeStore()
		let target = Date().addingTimeInterval(6423)
		store.start(.clockTime(target))
		let t = store.timers[0]
		XCTAssertEqual(t.kind, .clockAlarm)
		XCTAssertEqual(t.fireDate, target)
	}

	func testSoonestTracksNearestFireDateSkippingPaused() {
		let store = makeStore()
		store.start(.duration(300))
		store.start(.duration(100))
		store.start(.duration(200))
		XCTAssertEqual(store.soonest?.total, 100)

		store.pause(id: store.timers[1].id)
		XCTAssertEqual(store.soonest?.total, 200)
	}

	func testPauseResumePreservesRemaining() {
		let store = makeStore()
		store.start(.duration(300))
		let id = store.timers[0].id

		store.pause(id: id)
		XCTAssertEqual(store.timers[0].state, .paused)
		XCTAssertEqual(store.timers[0].remaining, 300, accuracy: 1)

		store.resume(id: id)
		XCTAssertEqual(store.timers[0].state, .running)
		XCTAssertEqual(store.timers[0].fireDate.timeIntervalSinceNow, 300, accuracy: 1)
	}

	func testAddMinute() {
		let store = makeStore()
		store.start(.duration(60))
		let id = store.timers[0].id
		store.addMinute(id: id)
		XCTAssertEqual(store.timers[0].fireDate.timeIntervalSinceNow, 120, accuracy: 1)
	}

	func testRestartResetsToFullDuration() {
		let store = makeStore()
		store.start(.duration(300))
		let id = store.timers[0].id
		store.addMinute(id: id)

		store.restart(id: id)
		XCTAssertEqual(store.timers[0].state, .running)
		XCTAssertEqual(store.timers[0].fireDate.timeIntervalSinceNow, 300, accuracy: 1)
	}

	func testRestartFromPausedRunsAgain() {
		let store = makeStore()
		store.start(.duration(300))
		let id = store.timers[0].id
		store.pause(id: id)

		store.restart(id: id)
		XCTAssertEqual(store.timers[0].state, .running)
		XCTAssertNil(store.timers[0].remainingWhenPaused)
		XCTAssertEqual(store.timers[0].fireDate.timeIntervalSinceNow, 300, accuracy: 1)
	}

	func testRestartIgnoresClockAlarm() {
		let store = makeStore()
		let target = Date().addingTimeInterval(6000)
		store.start(.clockTime(target))

		store.restart(id: store.timers[0].id)
		XCTAssertEqual(store.timers[0].fireDate, target)
	}

	func testFireTransitionsToRingingThenRemovesAfterTenSeconds() {
		let store = makeStore()
		var firedNames: [String] = []
		var endedNames: [String] = []
		store.onFire = { firedNames.append($0.displayName) }
		store.onRingEnd = { endedNames.append($0.displayName) }

		store.start(.duration(5))
		let fireDate = store.timers[0].fireDate

		store.tick(now: fireDate.addingTimeInterval(1))
		XCTAssertEqual(store.timers[0].state, .ringing)
		XCTAssertEqual(firedNames.count, 1)
		XCTAssertEqual(store.soonest?.state, .ringing)

		store.tick(now: fireDate.addingTimeInterval(1 + TimerStore.ringDuration))
		XCTAssertEqual(store.count, 0)
		XCTAssertEqual(endedNames.count, 1)
	}

	func testStopRingingRemovesEarly() {
		let store = makeStore()
		var rangEnded = false
		store.onRingEnd = { _ in rangEnded = true }

		store.start(.duration(1))
		let fireDate = store.timers[0].fireDate
		store.tick(now: fireDate.addingTimeInterval(1))
		XCTAssertEqual(store.timers[0].state, .ringing)

		store.stopRinging(id: store.timers[0].id)
		XCTAssertEqual(store.count, 0)
		XCTAssertTrue(rangEnded)
	}

	func testCancelRemoves() {
		let store = makeStore()
		store.start(.duration(100))
		store.cancel(id: store.timers[0].id)
		XCTAssertEqual(store.count, 0)
	}
}
