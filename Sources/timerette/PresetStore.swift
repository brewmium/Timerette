import Foundation

// MARK: - Preset model

struct Preset: Codable, Identifiable {
	let id: UUID
	var label: String
	var total: TimeInterval
	var sortOrder: Int
}

// MARK: - Preset store

// CRUD + JSON persistence in Application Support. Seeds defaults on first
// run so the panel is never empty; an intentionally emptied list stays empty.
class PresetStore {
	private(set) var presets: [Preset] = []
	private let fileURL: URL

	var onChange: (() -> Void)?

	init(directory: URL? = nil) {
		let dir: URL
		if let directory {
			dir = directory
		} else {
			let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
			dir = appSupport.appendingPathComponent("Timerette")
		}
		try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
		fileURL = dir.appendingPathComponent("presets.json")
		load()
	}

	// MARK: CRUD

	func add(label: String, total: TimeInterval) {
		let order = (presets.map { $0.sortOrder }.max() ?? -1) + 1
		presets.append(Preset(id: UUID(), label: label, total: total, sortOrder: order))
		save()
		onChange?()
	}

	func update(id: UUID, label: String, total: TimeInterval) {
		guard let i = presets.firstIndex(where: { $0.id == id }) else { return }
		presets[i].label = label
		presets[i].total = total
		save()
		onChange?()
	}

	func remove(id: UUID) {
		presets.removeAll { $0.id == id }
		save()
		onChange?()
	}

	// MARK: Persistence

	private func load() {
		guard let data = try? Data(contentsOf: fileURL),
			let loaded = try? JSONDecoder().decode([Preset].self, from: data)
		else {
			seedDefaults()
			return
		}
		presets = loaded.sorted { $0.sortOrder < $1.sortOrder }
	}

	private func seedDefaults() {
		presets = [
			Preset(id: UUID(), label: "Tea", total: 3 * 60, sortOrder: 0),
			Preset(id: UUID(), label: "Coffee", total: 4 * 60, sortOrder: 1),
			Preset(id: UUID(), label: "Pomodoro", total: 25 * 60, sortOrder: 2),
			Preset(id: UUID(), label: "Break", total: 10 * 60, sortOrder: 3),
		]
		save()
	}

	private func save() {
		let encoder = JSONEncoder()
		encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
		guard let data = try? encoder.encode(presets) else { return }
		try? data.write(to: fileURL)
	}
}
