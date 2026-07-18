import Foundation

// MARK: - Preset model

struct Preset: Codable, Identifiable {
	let id: UUID
	var label: String?
	var total: TimeInterval
	var sortOrder: Int

	var hasLabel: Bool {
		!(label ?? "").isEmpty
	}

	// Unlabeled presets go by their duration, same voice as CountdownTimer
	var displayName: String {
		hasLabel ? label! : "\(TimeFormat.compact(total)) timer"
	}
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

	@discardableResult
	func add(label: String? = nil, total: TimeInterval) -> Preset {
		let order = (presets.map { $0.sortOrder }.max() ?? -1) + 1
		let preset = Preset(id: UUID(), label: normalized(label), total: total, sortOrder: order)
		presets.append(preset)
		save()
		onChange?()
		return preset
	}

	func update(id: UUID, label: String?, total: TimeInterval) {
		guard let i = presets.firstIndex(where: { $0.id == id }) else { return }
		presets[i].label = normalized(label)
		presets[i].total = total
		save()
		onChange?()
	}

	func remove(id: UUID) {
		presets.removeAll { $0.id == id }
		save()
		onChange?()
	}

	// Reorder: `to` is the insertion index as shown before the row is lifted
	// (NSTableView drop semantics)
	func move(from: Int, to: Int) {
		guard from >= 0, from < presets.count, to >= 0, to <= presets.count, from != to else { return }
		let preset = presets.remove(at: from)
		presets.insert(preset, at: to > from ? to - 1 : to)
		for i in presets.indices {
			presets[i].sortOrder = i
		}
		save()
		onChange?()
	}

	private func normalized(_ label: String?) -> String? {
		let trimmed = (label ?? "").trimmingCharacters(in: .whitespaces)
		return trimmed.isEmpty ? nil : trimmed
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
		let totals: [TimeInterval] = [60, 180, 300, 600, 900, 1800, 3600]
		presets = totals.enumerated().map { i, total in
			Preset(id: UUID(), label: nil, total: total, sortOrder: i)
		}
		save()
	}

	private func save() {
		let encoder = JSONEncoder()
		encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
		guard let data = try? encoder.encode(presets) else { return }
		try? data.write(to: fileURL, options: [.atomic])
	}
}
