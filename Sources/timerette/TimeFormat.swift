import Foundation

// MARK: - Countdown formatting

enum TimeFormat {
	// One compact formatter used everywhere a duration shows: menu bar, menu
	// rows, panel preview, presets. Labeled d/h/m/s, no colons, largest to
	// smallest non-zero unit, interior zeros kept, end zeros trimmed.
	// 36s / 5m 14s / 2h 0m 7s / 4d 3h 3m 1s
	static func compact(_ interval: TimeInterval) -> String {
		let total = max(0, Int(interval.rounded(.up)))
		let d = total / 86400
		let h = (total % 86400) / 3600
		let m = (total % 3600) / 60
		let s = total % 60
		var parts: [(value: Int, unit: String)] = [(d, "d"), (h, "h"), (m, "m"), (s, "s")]
		while parts.count > 1 && parts.first!.value == 0 { parts.removeFirst() }
		while parts.count > 1 && parts.last!.value == 0 { parts.removeLast() }
		return parts.map { "\($0.value)\($0.unit)" }.joined(separator: " ")
	}

	// "3:00 PM" -- target display for clock alarms
	private static let clockFormatter: DateFormatter = {
		let f = DateFormatter()
		f.dateStyle = .none
		f.timeStyle = .short
		return f
	}()

	static func clockString(_ date: Date) -> String {
		clockFormatter.string(from: date)
	}
}
