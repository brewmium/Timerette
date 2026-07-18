import XCTest
@testable import timerette

final class PresetStoreTests: XCTestCase {
	private var dir: URL!

	override func setUp() {
		dir = FileManager.default.temporaryDirectory
			.appendingPathComponent("timerette-tests-\(UUID().uuidString)")
	}

	override func tearDown() {
		try? FileManager.default.removeItem(at: dir)
	}

	func testSeedsDefaultsOnFirstRun() {
		let store = PresetStore(directory: dir)
		XCTAssertEqual(store.presets.map { $0.total }, [60, 180, 300, 600, 900, 1800, 3600])
		XCTAssertTrue(store.presets.allSatisfy { $0.label == nil })
		XCTAssertEqual(store.presets.map { $0.displayName },
			["1m timer", "3m timer", "5m timer", "10m timer", "15m timer", "30m timer", "1h timer"])
	}

	func testCrudSurvivesRelaunch() {
		let store = PresetStore(directory: dir)
		store.add(label: "Eggs", total: 390)
		store.update(id: store.presets[0].id, label: "Green Tea", total: 120)
		store.remove(id: store.presets[1].id)

		let reloaded = PresetStore(directory: dir)
		XCTAssertEqual(reloaded.presets.first?.label, "Green Tea")
		XCTAssertEqual(reloaded.presets.first?.total, 120)
		XCTAssertEqual(reloaded.presets.last?.label, "Eggs")
		XCTAssertEqual(reloaded.presets.count, 7)
		XCTAssertFalse(reloaded.presets.contains { $0.total == 180 })
	}

	func testLabelIsOptionalAndBlankNormalizesToNil() {
		let store = PresetStore(directory: dir)
		let added = store.add(label: "   ", total: 420)
		XCTAssertNil(added.label)
		XCTAssertEqual(added.displayName, "7m timer")

		store.update(id: added.id, label: "Soup", total: 420)
		XCTAssertEqual(store.presets.last?.displayName, "Soup")

		store.update(id: added.id, label: "", total: 420)
		XCTAssertNil(store.presets.last?.label, "clearing the label reverts to unlabeled")
	}

	func testMoveReordersAndPersists() {
		let store = PresetStore(directory: dir)
		// [1m 3m 5m 10m 15m 30m 1h] -- lift 1h (6) and drop above 3m (row 1)
		store.move(from: 6, to: 1)
		XCTAssertEqual(store.presets.map { $0.total }, [60, 3600, 180, 300, 600, 900, 1800])

		// lift 1m (0) and drop at the very end (insertion index == count)
		store.move(from: 0, to: 7)
		XCTAssertEqual(store.presets.map { $0.total }, [3600, 180, 300, 600, 900, 1800, 60])

		let reloaded = PresetStore(directory: dir)
		XCTAssertEqual(reloaded.presets.map { $0.total }, [3600, 180, 300, 600, 900, 1800, 60])
		XCTAssertEqual(reloaded.presets.map { $0.sortOrder }, Array(0..<7))
	}

	func testEmptiedListStaysEmpty() {
		let store = PresetStore(directory: dir)
		for preset in store.presets {
			store.remove(id: preset.id)
		}
		XCTAssertTrue(store.presets.isEmpty)

		let reloaded = PresetStore(directory: dir)
		XCTAssertTrue(reloaded.presets.isEmpty, "deleting all presets must not re-seed defaults")
	}

	func testSortOrderContinuesAfterAdds() {
		let store = PresetStore(directory: dir)
		store.add(label: "A", total: 60)
		store.add(label: "B", total: 60)
		let orders = store.presets.map { $0.sortOrder }
		XCTAssertEqual(orders, orders.sorted())
		XCTAssertEqual(Set(orders).count, orders.count)
	}
}
