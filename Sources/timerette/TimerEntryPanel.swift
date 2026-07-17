import Cocoa

// MARK: - Screen mode

enum ScreenMode: Int, CaseIterable {
	case mouseScreen = 0, frontWindow = 1

	var label: String { ["Mouse Screen", "Front Window Screen"][rawValue] }
}

// MARK: - Entry row model

struct EntryRow {
	let title: String
	let detail: String
	let muted: Bool
	let action: (() -> Void)?
}

// MARK: - Table view that never steals focus

class PassthroughTableView: NSTableView {
	override var acceptsFirstResponder: Bool { false }
}

// MARK: - Custom row selection highlight

class EntryRowView: NSTableRowView {
	override func drawSelection(in dirtyRect: NSRect) {
		if selectionHighlightStyle != .none {
			NSColor.white.withAlphaComponent(0.15).setFill()
			NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 1), xRadius: 6, yRadius: 6).fill()
		}
	}
}

// MARK: - Vertically centered text field cell

class VerticalCenterTextFieldCell: NSTextFieldCell {
	override func titleRect(forBounds rect: NSRect) -> NSRect {
		var r = super.titleRect(forBounds: rect)
		let textH = cellSize(forBounds: rect).height
		let delta = r.height - textH
		if delta > 0 {
			r.origin.y += delta / 2
			r.size.height -= delta
		}
		return r
	}

	override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
		super.drawInterior(withFrame: titleRect(forBounds: cellFrame), in: controlView)
	}

	override func select(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText,
		delegate: Any?, start selStart: Int, length selLength: Int)
	{
		super.select(withFrame: titleRect(forBounds: rect), in: controlView,
			editor: textObj, delegate: delegate, start: selStart, length: selLength)
	}

	override func edit(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText,
		delegate: Any?, event: NSEvent?)
	{
		super.edit(withFrame: titleRect(forBounds: rect), in: controlView,
			editor: textObj, delegate: delegate, event: event)
	}
}

// MARK: - Timer entry panel

class TimerEntryPanel: NSPanel, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
	static let accent = NSColor(red: 0xFF/255.0, green: 0x8A/255.0, blue: 0x00/255.0, alpha: 1.0)

	private let inputField: NSTextField
	private let iconView: NSImageView
	private let startButton: NSButton
	private let rowsTable: PassthroughTableView
	private let scrollView: NSScrollView
	private let visualEffect: NSVisualEffectView
	private var rows: [EntryRow] = []
	private var previousApp: NSRunningApplication?

	var onStart: ((TimerInput, String?) -> Void)?
	var presetsProvider: (() -> [Preset])?

	private let panelWidth: CGFloat = 561
	private let fieldHeight: CGFloat = 48
	private let rowHeight: CGFloat = 40
	private let maxVisibleRows = 8
	private let pad: CGFloat = 8
	private let gutter: CGFloat = 20
	private let startButtonWidth: CGFloat = 52
	private(set) var screenMode: ScreenMode

	init() {
		self.screenMode = ScreenMode(rawValue: UserDefaults.standard.integer(forKey: "screenMode")) ?? .mouseScreen
		inputField = NSTextField()
		iconView = NSImageView()
		startButton = NSButton()
		rowsTable = PassthroughTableView()
		scrollView = NSScrollView()
		visualEffect = NSVisualEffectView()

		let initialHeight = fieldHeight + pad * 2
		super.init(
			contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: initialHeight),
			styleMask: [.nonactivatingPanel],
			backing: .buffered,
			defer: false
		)

		level = .floating
		hasShadow = true
		backgroundColor = .clear
		isOpaque = false
		hidesOnDeactivate = false
		becomesKeyOnlyIfNeeded = false

		setupViews()
	}

	override var canBecomeKey: Bool { true }

	// MARK: View setup

	private func setupViews() {
		let bounds = contentView!.bounds

		// Vibrancy background
		visualEffect.frame = bounds
		visualEffect.autoresizingMask = [.width, .height]
		visualEffect.material = .hudWindow
		visualEffect.state = .active
		visualEffect.appearance = NSAppearance(named: .darkAqua)
		visualEffect.wantsLayer = true
		visualEffect.layer?.cornerRadius = 12
		visualEffect.layer?.masksToBounds = true
		visualEffect.layer?.borderWidth = 1.5
		visualEffect.layer?.borderColor = Self.accent.cgColor
		contentView?.addSubview(visualEffect)

		// Stopwatch icon
		let iconSz: CGFloat = 22
		let iconY = bounds.height - pad - fieldHeight + (fieldHeight - iconSz) / 2
		iconView.frame = NSRect(x: gutter, y: iconY, width: iconSz, height: iconSz)
		let config = NSImage.SymbolConfiguration(pointSize: iconSz, weight: .medium)
		iconView.image = NSImage(systemSymbolName: "stopwatch", accessibilityDescription: "Timerette")?
			.withSymbolConfiguration(config)
		iconView.contentTintColor = .secondaryLabelColor
		iconView.imageScaling = .scaleProportionallyUpOrDown
		iconView.autoresizingMask = [.minYMargin]
		visualEffect.addSubview(iconView)

		// Input field
		let fieldX = gutter + iconSz + pad
		let fieldY = bounds.height - pad - fieldHeight
		let fieldW = bounds.width - fieldX - gutter - startButtonWidth - pad
		inputField.frame = NSRect(x: fieldX, y: fieldY, width: fieldW, height: fieldHeight)
		inputField.autoresizingMask = [.width, .minYMargin]
		let centeredCell = VerticalCenterTextFieldCell()
		centeredCell.isEditable = true
		centeredCell.isSelectable = true
		centeredCell.isBordered = false
		centeredCell.isBezeled = false
		centeredCell.drawsBackground = false
		centeredCell.focusRingType = .none
		inputField.cell = centeredCell
		inputField.font = .systemFont(ofSize: 24, weight: .light)
		inputField.placeholderAttributedString = NSAttributedString(
			string: "2.5, 90s, 1h30m, 3:30pm...",
			attributes: [
				.foregroundColor: NSColor.secondaryLabelColor,
				.font: NSFont.systemFont(ofSize: 24, weight: .light),
			]
		)
		inputField.isBordered = false
		inputField.isBezeled = false
		inputField.drawsBackground = false
		inputField.focusRingType = .none
		inputField.textColor = .white
		inputField.delegate = self
		visualEffect.addSubview(inputField)

		// Start button at the field's right edge (same as Return)
		let btnH: CGFloat = 24
		let btnY = fieldY + (fieldHeight - btnH) / 2
		startButton.frame = NSRect(x: bounds.width - gutter - startButtonWidth, y: btnY,
			width: startButtonWidth, height: btnH)
		startButton.autoresizingMask = [.minXMargin, .minYMargin]
		startButton.isBordered = false
		startButton.attributedTitle = NSAttributedString(
			string: "Start",
			attributes: [
				.foregroundColor: Self.accent,
				.font: NSFont.systemFont(ofSize: 14, weight: .semibold),
			]
		)
		startButton.target = self
		startButton.action = #selector(startClicked)
		visualEffect.addSubview(startButton)

		// Rows table in scroll view
		let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("rows"))
		column.width = panelWidth - pad * 2
		rowsTable.addTableColumn(column)
		rowsTable.headerView = nil
		rowsTable.dataSource = self
		rowsTable.delegate = self
		rowsTable.backgroundColor = .clear
		rowsTable.rowHeight = rowHeight
		rowsTable.intercellSpacing = NSSize(width: 0, height: 2)
		rowsTable.selectionHighlightStyle = .regular
		rowsTable.gridStyleMask = []
		rowsTable.target = self
		rowsTable.action = #selector(tableClicked)

		scrollView.documentView = rowsTable
		scrollView.hasVerticalScroller = false
		scrollView.hasHorizontalScroller = false
		scrollView.drawsBackground = false
		scrollView.borderType = .noBorder
		scrollView.frame = NSRect(x: pad, y: pad, width: bounds.width - pad * 2, height: 0)
		scrollView.autoresizingMask = [.width, .height]
		scrollView.isHidden = true
		visualEffect.addSubview(scrollView)
	}

	// MARK: Show / Dismiss

	func showPanel() {
		previousApp = NSWorkspace.shared.frontmostApplication
		inputField.stringValue = ""
		refreshRows()

		let screen: NSScreen
		if screenMode == .mouseScreen {
			let mouseLocation = NSEvent.mouseLocation
			screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main!
		} else {
			screen = NSScreen.main ?? NSScreen.screens[0]
		}
		let sf = screen.visibleFrame
		let h = frame.height
		let x = sf.midX - panelWidth / 2
		let y = sf.origin.y + sf.height * 3 / 4 - h / 2

		setFrame(NSRect(x: x, y: y, width: panelWidth, height: h), display: true)

		NSApp.activate(ignoringOtherApps: true)
		makeKeyAndOrderFront(nil)
		makeFirstResponder(inputField)

		NotificationCenter.default.addObserver(
			self, selector: #selector(windowDidResignKey),
			name: NSWindow.didResignKeyNotification, object: self
		)
	}

	func dismiss(restoreFocus: Bool = true) {
		NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: self)
		orderOut(nil)
		if restoreFocus {
			previousApp?.activate(options: [])
		}
		previousApp = nil
	}

	@objc private func windowDidResignKey(_ notification: Notification) {
		dismiss()
	}

	// MARK: Rows

	func refreshVisibleRows() {
		if isVisible {
			refreshRows()
		}
	}

	private func refreshRows() {
		let query = inputField.stringValue.trimmingCharacters(in: .whitespaces)
		rows = []

		if query.isEmpty {
			for preset in presetsProvider?() ?? [] {
				rows.append(EntryRow(
					title: preset.label,
					detail: TimeFormat.compact(preset.total),
					muted: false,
					action: { [weak self] in self?.onStart?(.duration(preset.total), preset.label) }
				))
			}
		} else if let input = InputParser.parse(query) {
			rows.append(EntryRow(
				title: input.previewTitle(),
				detail: "Return",
				muted: false,
				action: { [weak self] in self?.onStart?(input, nil) }
			))
		} else {
			rows.append(EntryRow(
				title: "Keep typing -- 2.5, 90s, 1h30m, 3:30pm...",
				detail: "",
				muted: true,
				action: nil
			))
		}

		rowsTable.reloadData()
		selectFirstSelectable()
		updatePanelSize()
	}

	private func selectFirstSelectable() {
		if let idx = rows.firstIndex(where: { !$0.muted }) {
			rowsTable.selectRowIndexes(IndexSet(integer: idx), byExtendingSelection: false)
		}
	}

	private func updatePanelSize() {
		let count = min(rows.count, maxVisibleRows)
		let tableH = CGFloat(count) * (rowHeight + 2)
		let newH: CGFloat

		if count > 0 {
			scrollView.isHidden = false
			newH = fieldHeight + pad * 3 + tableH
		} else {
			scrollView.isHidden = true
			newH = fieldHeight + pad * 2
		}

		var f = frame
		let top = f.maxY
		f.size.height = newH
		f.origin.y = top - newH
		setFrame(f, display: true, animate: true)
	}

	// MARK: Start

	private func startSelected() {
		let row = rowsTable.selectedRow
		guard row >= 0, row < rows.count, let action = rows[row].action else { return }
		dismiss()
		action()
	}

	@objc private func tableClicked() {
		let row = rowsTable.clickedRow
		guard row >= 0, row < rows.count, let action = rows[row].action else { return }
		dismiss()
		action()
	}

	@objc private func startClicked() {
		startSelected()
	}

	// MARK: NSTextFieldDelegate

	func controlTextDidChange(_ notification: Notification) {
		refreshRows()
	}

	func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
		if sel == #selector(moveUp(_:)) {
			let row = max(0, rowsTable.selectedRow - 1)
			selectRow(row)
			return true
		}
		if sel == #selector(moveDown(_:)) {
			let row = min(rows.count - 1, rowsTable.selectedRow + 1)
			if row >= 0 {
				selectRow(row)
			}
			return true
		}
		if sel == #selector(insertNewline(_:)) {
			startSelected()
			return true
		}
		if sel == #selector(cancelOperation(_:)) {
			dismiss()
			return true
		}
		return false
	}

	private func selectRow(_ row: Int) {
		guard row >= 0, row < rows.count, !rows[row].muted else { return }
		rowsTable.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
		rowsTable.scrollRowToVisible(row)
	}

	// MARK: NSTableViewDataSource

	func numberOfRows(in tableView: NSTableView) -> Int {
		rows.count
	}

	// MARK: NSTableViewDelegate

	func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
		EntryRowView()
	}

	func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
		row >= 0 && row < rows.count && !rows[row].muted
	}

	func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
		let entry = rows[row]
		let cellW = panelWidth - pad * 2
		let rightEdge = cellW - gutter * 2
		let titleFS: CGFloat = 15
		let titleH = ceil(titleFS * 1.4)
		let titleY = (rowHeight - titleH) / 2

		let cell = NSView()

		let titleLabel = NSTextField(labelWithString: entry.title)
		titleLabel.frame = NSRect(x: gutter, y: titleY, width: rightEdge - gutter - 60, height: titleH)
		titleLabel.font = .systemFont(ofSize: titleFS, weight: .medium)
		titleLabel.textColor = entry.muted ? .secondaryLabelColor : .labelColor
		titleLabel.lineBreakMode = .byTruncatingTail
		cell.addSubview(titleLabel)

		if !entry.detail.isEmpty {
			let detailLabel = NSTextField(labelWithString: entry.detail)
			detailLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
			detailLabel.textColor = .secondaryLabelColor
			detailLabel.sizeToFit()
			detailLabel.frame.origin = NSPoint(x: rightEdge - detailLabel.frame.width, y: titleY + 2)
			cell.addSubview(detailLabel)
		}

		return cell
	}

	func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
		rowHeight
	}

	// MARK: Settings

	func setScreenMode(_ mode: ScreenMode) {
		screenMode = mode
		UserDefaults.standard.set(mode.rawValue, forKey: "screenMode")
	}
}
