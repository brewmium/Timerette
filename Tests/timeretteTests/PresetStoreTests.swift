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
		XCTAssertEqual(store.presets.map { $0.label }, ["Tea", "Coffee", "Pomodoro", "Break"])
		XCTAssertEqual(store.presets.map { $0.total }, [180, 240, 1500, 600])
	}

	func testCrudSurvivesRelaunch() {
		let store = PresetStore(directory: dir)
		store.add(label: "Eggs", total: 390)
		store.update(id: store.presets[0].id, label: "Green Tea", total: 120)
		store.remove(id: store.presets[1].id)

		let reloaded = PresetStore(directory: dir)
		XCTAssertEqual(reloaded.presets.map { $0.label }, ["Green Tea", "Pomodoro", "Break", "Eggs"])
		XCTAssertEqual(reloaded.presets.map { $0.total }, [120, 1500, 600, 390])
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
