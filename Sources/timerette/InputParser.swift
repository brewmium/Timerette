import Foundation

// MARK: - Parsed input

enum TimerInput: Equatable {
	case duration(TimeInterval)
	case clockTime(Date)
}

extension TimerInput {
	// Live preview row text in the entry panel
	func previewTitle(label: String? = nil, now: Date = Date()) -> String {
		let suffix = label.map { " \"\($0)\"" } ?? ""
		switch self {
		case .duration(let span):
			return "Start a \(TimeFormat.compact(span)) timer\(suffix)"
		case .clockTime(let date):
			let remaining = date.timeIntervalSince(now)
			return "Alarm at \(TimeFormat.clockString(date))\(suffix)  (in \(TimeFormat.compact(remaining)))"
		}
	}
}

// MARK: - Input parser

// Two tracks. The one rule: a colon or an am/pm marker means clock time;
// everything else is a duration, and a bare number is minutes.
enum InputParser {
	static let maxDuration: TimeInterval = 99 * 86400

	static func parse(_ raw: String, now: Date = Date(), calendar: Calendar = .current) -> TimerInput? {
		let s = raw.trimmingCharacters(in: .whitespaces).lowercased()
		guard !s.isEmpty else { return nil }

		if isClockShaped(s) {
			guard let date = resolveClockTime(s, now: now, calendar: calendar) else { return nil }
			return .clockTime(date)
		}
		guard let span = parseDuration(s) else { return nil }
		return .duration(span)
	}

	// Inline labels: "2.5 tea" -> a 2m 30s timer labeled "tea". The longest
	// parseable prefix wins; the remainder is the label and must not begin
	// with a digit (so "15 45" stays rejected).
	static func parseWithLabel(_ raw: String, now: Date = Date(), calendar: Calendar = .current)
		-> (input: TimerInput, label: String?)?
	{
		if let input = parse(raw, now: now, calendar: calendar) {
			return (input, nil)
		}
		let words = raw.trimmingCharacters(in: .whitespaces)
			.split(whereSeparator: { $0.isWhitespace })
		guard words.count >= 2 else { return nil }
		for split in stride(from: words.count - 1, through: 1, by: -1) {
			let tail = words[split...].joined(separator: " ")
			guard let first = tail.first, !first.isNumber else { continue }
			let head = words[0..<split].joined(separator: " ")
			if let input = parse(head, now: now, calendar: calendar) {
				return (input, tail)
			}
		}
		return nil
	}

	// MARK: Clock track

	private static func isClockShaped(_ s: String) -> Bool {
		if s.contains(":") { return true }
		return s.range(of: "(am|pm|a|p)$", options: .regularExpression) != nil
	}

	// H, H:MM, HH:MM with optional meridiem (a/p/am/pm). Without a meridiem
	// the hour is 24-hour (needs the colon to be clock-shaped at all).
	// Resolved to the next future occurrence; Calendar handles DST.
	private static func resolveClockTime(_ s: String, now: Date, calendar: Calendar) -> Date? {
		guard let match = s.wholeMatch(pattern: "^(\\d{1,2})(?::([0-5]\\d))?\\s*(am|pm|a|p)?$") else { return nil }
		guard let hourRaw = Int(match[1]) else { return nil }
		let minute = match[2].isEmpty ? 0 : (Int(match[2]) ?? 0)
		let meridiem = match[3]

		let hour: Int
		if meridiem.isEmpty {
			guard s.contains(":"), (0...23).contains(hourRaw) else { return nil }
			hour = hourRaw
		} else {
			guard (1...12).contains(hourRaw) else { return nil }
			let isPM = meridiem.hasPrefix("p")
			hour = (hourRaw % 12) + (isPM ? 12 : 0)
		}

		var comps = DateComponents()
		comps.hour = hour
		comps.minute = minute
		comps.second = 0
		return calendar.nextDate(after: now, matching: comps, matchingPolicy: .nextTime)
	}

	// MARK: Duration track

	private struct Component {
		let value: Double
		let unit: Character?
	}

	private static let unitSeconds: [Character: Double] = ["d": 86400, "h": 3600, "m": 60, "s": 1]
	private static let nextSmaller: [Character: Character] = ["d": "h", "h": "m", "m": "s"]

	// Number(+optional unit) runs: 2.5 / 90s / 1h30m / 2h30 / 3d22h.
	// A lone unit-less number is minutes; a trailing unit-less number after a
	// unit is the next-smaller unit; a unit-less number anywhere else rejects.
	private static func parseDuration(_ s: String) -> TimeInterval? {
		var comps: [Component] = []
		var i = s.startIndex
		while i < s.endIndex {
			if s[i] == " " || s[i] == "\t" {
				i = s.index(after: i)
				continue
			}
			var numStr = ""
			var j = i
			while j < s.endIndex, s[j].isNumber || s[j] == "." {
				numStr.append(s[j])
				j = s.index(after: j)
			}
			guard !numStr.isEmpty, let value = Double(numStr) else { return nil }
			var k = j
			while k < s.endIndex, s[k] == " " || s[k] == "\t" {
				k = s.index(after: k)
			}
			if k < s.endIndex, unitSeconds[s[k]] != nil {
				comps.append(Component(value: value, unit: s[k]))
				i = s.index(after: k)
			} else {
				comps.append(Component(value: value, unit: nil))
				i = j
			}
		}

		guard !comps.isEmpty else { return nil }

		var total: Double = 0
		if comps.count == 1, comps[0].unit == nil {
			total = comps[0].value * 60
		} else {
			for (idx, comp) in comps.enumerated() {
				if let u = comp.unit {
					total += comp.value * unitSeconds[u]!
				} else {
					guard idx == comps.count - 1, idx > 0,
						let prev = comps[idx - 1].unit,
						let smaller = nextSmaller[prev]
					else { return nil }
					total += comp.value * unitSeconds[smaller]!
				}
			}
		}

		total = min(total, maxDuration).rounded()
		guard total > 0 else { return nil }
		return total
	}
}

// MARK: - Small regex helper

private extension String {
	// Whole-string match; returns captured groups by 1-based index ("" if absent)
	func wholeMatch(pattern: String) -> RegexGroups? {
		guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
		let range = NSRange(startIndex..., in: self)
		guard let m = regex.firstMatch(in: self, range: range), m.range == range else { return nil }
		return RegexGroups(match: m, source: self)
	}
}

private struct RegexGroups {
	let match: NSTextCheckingResult
	let source: String

	subscript(index: Int) -> String {
		guard index < match.numberOfRanges,
			let r = Range(match.range(at: index), in: source)
		else { return "" }
		return String(source[r])
	}
}
