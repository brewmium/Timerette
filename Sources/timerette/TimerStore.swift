import Foundation

// MARK: - Timer store

// Owns active timers, drives the 1-second tick, fires them into ringing.
class TimerStore {
	private(set) var timers: [CountdownTimer] = []

	var onChange: (() -> Void)?
	var onFire: ((CountdownTimer) -> Void)?
	var onRingEnd: ((CountdownTimer) -> Void)?

	static let ringDuration: TimeInterval = 10
	private var ringDeadlines: [UUID: Date] = [:]
	private var tickTimer: Timer?
	private let fileURL: URL

	init(directory: URL? = nil) {
		let dir: URL
		if let directory {
			dir = directory
		} else {
			let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
			dir = appSupport.appendingPathComponent("Timerette")
		}
		try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
		fileURL = dir.appendingPathComponent("timers.json")
		restore()
	}

	// MARK: Start / control

	func start(_ input: TimerInput, label: String? = nil) {
		let timer: CountdownTimer
		switch input {
		case .duration(let span):
			timer = CountdownTimer(id: UUID(), label: label, kind: .durationTimer,
				total: span, fireDate: Date().addingTimeInterval(span),
				state: .running, remainingWhenPaused: nil)
		case .clockTime(let date):
			timer = CountdownTimer(id: UUID(), label: label, kind: .clockAlarm,
				total: max(0, date.timeIntervalSinceNow), fireDate: date,
				state: .running, remainingWhenPaused: nil)
		}
		timers.append(timer)
		changed()
	}

	func pause(id: UUID) {
		guard let i = index(of: id), timers[i].state == .running else { return }
		timers[i].remainingWhenPaused = max(0, timers[i].fireDate.timeIntervalSinceNow)
		timers[i].state = .paused
		changed()
	}

	func resume(id: UUID) {
		guard let i = index(of: id), timers[i].state == .paused else { return }
		timers[i].fireDate = Date().addingTimeInterval(timers[i].remainingWhenPaused ?? 0)
		timers[i].remainingWhenPaused = nil
		timers[i].state = .running
		changed()
	}

	func cancel(id: UUID) {
		guard let i = index(of: id) else { return }
		let timer = timers[i]
		timers.remove(at: i)
		if timer.state == .ringing {
			ringDeadlines[id] = nil
			onRingEnd?(timer)
		}
		changed()
	}

	func addMinute(id: UUID) {
		guard let i = index(of: id) else { return }
		switch timers[i].state {
		case .running:
			timers[i].fireDate += 60
		case .paused:
			timers[i].remainingWhenPaused = (timers[i].remainingWhenPaused ?? 0) + 60
		case .ringing:
			// +1m on a ringing timer puts a minute back on the clock
			ringDeadlines[id] = nil
			onRingEnd?(timers[i])
			timers[i].state = .running
			timers[i].fireDate = Date().addingTimeInterval(60)
		}
		changed()
	}

	func stopRinging(id: UUID) {
		guard let i = index(of: id), timers[i].state == .ringing else { return }
		let timer = timers[i]
		timers.remove(at: i)
		ringDeadlines[id] = nil
		onRingEnd?(timer)
		changed()
	}

	// MARK: Queries

	// Nearest fireDate among non-paused timers drives the menu-bar text; a
	// ringing timer has a past fireDate so it naturally wins and reads 0s.
	var soonest: CountdownTimer? {
		timers.filter { $0.state != .paused }.min { $0.fireDate < $1.fireDate }
	}

	var count: Int { timers.count }

	func timer(id: UUID) -> CountdownTimer? {
		timers.first { $0.id == id }
	}

	private func index(of id: UUID) -> Int? {
		timers.firstIndex { $0.id == id }
	}

	// MARK: Tick

	private func ensureTicking() {
		if timers.isEmpty {
			tickTimer?.invalidate()
			tickTimer = nil
			return
		}
		guard tickTimer == nil else { return }
		let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
			self?.tick()
		}
		// .common mode keeps the countdown updating while a menu is open or a
		// window is being dragged
		RunLoop.main.add(t, forMode: .common)
		tickTimer = t
	}

	func tick(now: Date = Date()) {
		var fired: [CountdownTimer] = []
		var ended: [CountdownTimer] = []

		for i in timers.indices {
			if timers[i].state == .running, timers[i].fireDate <= now {
				timers[i].state = .ringing
				ringDeadlines[timers[i].id] = now.addingTimeInterval(Self.ringDuration)
				fired.append(timers[i])
			}
		}

		for (id, deadline) in ringDeadlines where deadline <= now {
			if let i = index(of: id) {
				ended.append(timers[i])
				timers.remove(at: i)
			}
			ringDeadlines[id] = nil
		}

		for t in fired { onFire?(t) }
		for t in ended { onRingEnd?(t) }
		if !fired.isEmpty || !ended.isEmpty {
			save()
		}
		ensureTicking()
		onChange?()
	}

	private func changed() {
		ensureTicking()
		save()
		onChange?()
	}

	// MARK: Persistence

	// Written on every change so a 3-day auction timer outlives a quit or a
	// reboot. Remaining time is derived from fireDate, so restore is just
	// "is the fireDate still ahead".
	private func save() {
		let encoder = JSONEncoder()
		encoder.dateEncodingStrategy = .iso8601
		encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
		guard let data = try? encoder.encode(timers) else { return }
		try? data.write(to: fileURL, options: [.atomic])
	}

	private func restore() {
		guard let data = try? Data(contentsOf: fileURL) else { return }
		let decoder = JSONDecoder()
		decoder.dateDecodingStrategy = .iso8601
		guard let saved = try? decoder.decode([CountdownTimer].self, from: data) else { return }

		let now = Date()
		timers = saved.compactMap { saved in
			var timer = saved
			switch timer.state {
			case .paused:
				return timer
			case .running, .ringing:
				// Re-arm if the fireDate is still ahead; drop anything that
				// expired while the app was not running -- no retroactive chime
				timer.state = .running
				return timer.fireDate > now ? timer : nil
			}
		}
		changed()
	}
}
