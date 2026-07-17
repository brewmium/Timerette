import Cocoa

// MARK: - Menu bar rendering

// Composes the status item: stopwatch icon, the soonest timer's remaining
// time in monospaced digits, and an orange count badge when 2+ timers run.
enum MenuBarView {
	static func render(statusItem: NSStatusItem, store: TimerStore) {
		guard let button = statusItem.button else { return }

		let count = store.count
		button.image = icon(badge: count >= 2 ? count : nil)

		if let soonest = store.soonest {
			button.attributedTitle = NSAttributedString(
				string: " " + TimeFormat.compact(soonest.remaining),
				attributes: [
					.font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular),
					.foregroundColor: NSColor.labelColor,
				]
			)
			button.imagePosition = .imageLeft
		} else {
			button.attributedTitle = NSAttributedString(string: "")
			button.imagePosition = .imageOnly
		}
	}

	static func icon(badge: Int?) -> NSImage {
		let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
		let glyph = NSImage(systemSymbolName: "stopwatch", accessibilityDescription: "Timerette")!
			.withSymbolConfiguration(config)!

		guard let badge else {
			glyph.isTemplate = true
			return glyph
		}

		// Colored badge means a non-template composite; it will not invert on
		// menu highlight (accepted v1 caveat -- spec 3.1)
		let glyphSize = glyph.size
		let badgeD: CGFloat = 12
		let canvas = NSSize(width: glyphSize.width + badgeD / 2 + 2, height: glyphSize.height + 3)
		let text = badge > 9 ? "9+" : "\(badge)"

		let img = NSImage(size: canvas, flipped: false) { _ in
			// Tint the glyph with labelColor at draw time so it tracks the
			// menu bar appearance
			let tinted = glyph.copy() as! NSImage
			tinted.lockFocus()
			NSColor.labelColor.set()
			NSRect(origin: .zero, size: glyphSize).fill(using: .sourceAtop)
			tinted.unlockFocus()
			tinted.draw(at: NSPoint(x: 0, y: 0), from: .zero, operation: .sourceOver, fraction: 1.0)

			let badgeRect = NSRect(
				x: canvas.width - badgeD,
				y: canvas.height - badgeD,
				width: badgeD, height: badgeD
			)
			TimerEntryPanel.accent.setFill()
			NSBezierPath(ovalIn: badgeRect).fill()

			let str = NSAttributedString(string: text, attributes: [
				.font: NSFont.systemFont(ofSize: 8, weight: .bold),
				.foregroundColor: NSColor.white,
			])
			let strSize = str.size()
			str.draw(at: NSPoint(
				x: badgeRect.midX - strSize.width / 2,
				y: badgeRect.midY - strSize.height / 2
			))
			return true
		}
		img.isTemplate = false
		return img
	}
}
