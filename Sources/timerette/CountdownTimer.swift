import Foundation

// MARK: - Timer model

enum TimerKind: String, Codable {
	case durationTimer, clockAlarm
}

enum TimerState: String, Codable {
	case running, paused, ringing
}

struct CountdownTimer: Codable, Identifiable {
	let id: UUID
	var label: String?
	let kind: TimerKind
	let total: TimeInterval
	var fireDate: Date
	var state: TimerState
	var remainingWhenPaused: TimeInterval?

	// Always fireDate - now, never a decremented counter -- correct across
	// sleep/wake and drift, and clock alarms and multi-day timers just work.
	var remaining: TimeInterval {
		state == .paused ? (remainingWhenPaused ?? 0) : fireDate.timeIntervalSinceNow
	}

	// "3:00 PM" -- display target for a clock alarm
	var targetString: String {
		TimeFormat.clockString(fireDate)
	}

	var displayName: String {
		if let label, !label.isEmpty { return label }
		switch kind {
		case .clockAlarm: return "Alarm \(targetString)"
		case .durationTimer: return "\(TimeFormat.compact(total)) timer"
		}
	}
}
