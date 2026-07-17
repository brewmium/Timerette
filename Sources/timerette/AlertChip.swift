import Cocoa

// MARK: - Alert chip

// Small always-on-top orange card near the menu bar: timer name, "Time's up",
// and a Stop. Shown when the chime would be inaudible (muted/zero volume) or
// notifications are unavailable, so a finished timer is never both silent and
// invisible. Auto-dismissed when ringing ends.
class AlertChip: NSPanel {
	let timerID: UUID
	var onStop: ((UUID) -> Void)?

	private static let chipWidth: CGFloat = 300
	private static let chipHeight: CGFloat = 64

	init(timer: CountdownTimer, index: Int) {
		self.timerID = timer.id

		super.init(
			contentRect: NSRect(x: 0, y: 0, width: Self.chipWidth, height: Self.chipHeight),
			styleMask: [.nonactivatingPanel],
			backing: .buffered,
			defer: false
		)

		isFloatingPanel = true
		level = .statusBar
		isOpaque = false
		backgroundColor = .clear
		hasShadow = true
		hidesOnDeactivate = false

		let card = NSView(frame: contentView!.bounds)
		card.autoresizingMask = [.width, .height]
		card.wantsLayer = true
		card.layer?.backgroundColor = TimerEntryPanel.accent.cgColor
		card.layer?.cornerRadius = 12
		contentView?.addSubview(card)

		let titleLabel = NSTextField(labelWithString: "Time's up")
		titleLabel.font = .systemFont(ofSize: 15, weight: .bold)
		titleLabel.textColor = .white
		titleLabel.frame = NSRect(x: 16, y: 34, width: 190, height: 20)
		titleLabel.lineBreakMode = .byTruncatingTail
		card.addSubview(titleLabel)

		let nameLabel = NSTextField(labelWithString: timer.displayName)
		nameLabel.font = .systemFont(ofSize: 12, weight: .medium)
		nameLabel.textColor = NSColor.white.withAlphaComponent(0.9)
		nameLabel.frame = NSRect(x: 16, y: 12, width: 190, height: 17)
		nameLabel.lineBreakMode = .byTruncatingTail
		card.addSubview(nameLabel)

		let stopButton = NSButton(frame: NSRect(x: Self.chipWidth - 76, y: (Self.chipHeight - 28) / 2, width: 60, height: 28))
		stopButton.isBordered = false
		stopButton.wantsLayer = true
		stopButton.layer?.backgroundColor = NSColor.white.cgColor
		stopButton.layer?.cornerRadius = 14
		stopButton.attributedTitle = NSAttributedString(
			string: "Stop",
			attributes: [
				.foregroundColor: TimerEntryPanel.accent,
				.font: NSFont.systemFont(ofSize: 13, weight: .semibold),
			]
		)
		stopButton.target = self
		stopButton.action = #selector(stopClicked)
		card.addSubview(stopButton)

		// Stack under the menu bar at the top right of the menu-bar screen
		let screen = NSScreen.screens.first ?? NSScreen.main!
		let sf = screen.visibleFrame
		let x = sf.maxX - Self.chipWidth - 16
		let y = sf.maxY - Self.chipHeight - 16 - CGFloat(index) * (Self.chipHeight + 10)
		setFrameOrigin(NSPoint(x: x, y: y))
	}

	func show() {
		orderFrontRegardless()
	}

	@objc private func stopClicked() {
		onStop?(timerID)
	}
}
