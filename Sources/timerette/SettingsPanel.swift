import Cocoa

// MARK: - Settings Panel

// One window for everything configurable. The preset list is the main
// section: click a cell and type -- edits commit when you leave the field
// (Return/Tab/click away), no separate save step. Drag rows to reorder,
// + adds a row, - removes the selected one. Labels are optional. Below it:
// hotkey, alert sound, launch at login.
class SettingsPanel: NSPanel, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
	private let presetStore: PresetStore
	private let alertSounds: [String]
	private var table: NSTableView!
	private var loginCheck: NSButton!
	private let statusLabel = NSTextField(labelWithString: "")
	private let hotkeyValueLabel = NSTextField(labelWithString: "")
	private let dragType = NSPasteboard.PasteboardType("com.brewmium.timerette.preset-row")

	// Wired by AppDelegate -- hotkey registration, sound choice, and login
	// item state all live there
	var hotkeyDisplay: (() -> String)?
	var onChangeHotkey: (() -> Void)?
	var onSelectSound: ((String) -> Void)?
	var launchAtLoginIsOn: (() -> Bool)?
	var onToggleLaunchAtLogin: (() -> Void)?

	init(presetStore: PresetStore, alertSounds: [String], selectedSound: String) {
		self.presetStore = presetStore
		self.alertSounds = alertSounds

		super.init(
			contentRect: NSRect(x: 0, y: 0, width: 420, height: 480),
			styleMask: [.titled, .closable],
			backing: .buffered,
			defer: false
		)

		title = "Settings"
		setupUI(selectedSound: selectedSound)
		table.reloadData()
		center()
	}

	func refreshHotkeyDisplay() {
		hotkeyValueLabel.stringValue = hotkeyDisplay?() ?? ""
	}

	// Closures are wired after init, so pull live state on first display
	override func makeKeyAndOrderFront(_ sender: Any?) {
		refreshHotkeyDisplay()
		loginCheck.state = (launchAtLoginIsOn?() ?? false) ? .on : .off
		super.makeKeyAndOrderFront(sender)
	}

	private func setupUI(selectedSound: String) {
		let content = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 480))
		contentView = content

		// Presets section
		let header = NSTextField(labelWithString: "Presets")
		header.font = .boldSystemFont(ofSize: 13)
		header.frame = NSRect(x: 20, y: 444, width: 380, height: 20)
		content.addSubview(header)

		table = NSTableView()
		let labelCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("label"))
		labelCol.title = "Label"
		labelCol.width = 230
		table.addTableColumn(labelCol)
		let durCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("duration"))
		durCol.title = "Duration"
		durCol.width = 120
		table.addTableColumn(durCol)
		table.rowHeight = 24
		table.dataSource = self
		table.delegate = self
		table.registerForDraggedTypes([dragType])

		let scroll = NSScrollView(frame: NSRect(x: 20, y: 204, width: 380, height: 230))
		scroll.documentView = table
		scroll.hasVerticalScroller = true
		content.addSubview(scroll)

		let addBtn = NSButton(title: "+", target: self, action: #selector(addPreset))
		addBtn.frame = NSRect(x: 20, y: 164, width: 32, height: 28)
		content.addSubview(addBtn)

		let removeBtn = NSButton(title: "-", target: self, action: #selector(removePreset))
		removeBtn.frame = NSRect(x: 56, y: 164, width: 32, height: 28)
		content.addSubview(removeBtn)

		let hint = NSTextField(labelWithString: "Click to edit. Drag to reorder. Labels are optional.")
		hint.textColor = .secondaryLabelColor
		hint.font = .systemFont(ofSize: 11)
		hint.frame = NSRect(x: 100, y: 168, width: 300, height: 17)
		content.addSubview(hint)

		// Status line (parse errors)
		statusLabel.frame = NSRect(x: 20, y: 140, width: 380, height: 18)
		statusLabel.textColor = .systemRed
		statusLabel.font = .systemFont(ofSize: 12)
		content.addSubview(statusLabel)

		let separator = NSBox(frame: NSRect(x: 20, y: 126, width: 380, height: 1))
		separator.boxType = .separator
		content.addSubview(separator)

		// Hotkey row
		let hotkeyLabel = NSTextField(labelWithString: "Hotkey:")
		hotkeyLabel.frame = NSRect(x: 20, y: 94, width: 70, height: 20)
		content.addSubview(hotkeyLabel)

		hotkeyValueLabel.font = .systemFont(ofSize: 13)
		hotkeyValueLabel.frame = NSRect(x: 95, y: 94, width: 110, height: 20)
		content.addSubview(hotkeyValueLabel)

		let changeBtn = NSButton(title: "Change...", target: self, action: #selector(changeHotkey))
		changeBtn.frame = NSRect(x: 210, y: 88, width: 110, height: 28)
		content.addSubview(changeBtn)

		// Alert sound row
		let soundLabel = NSTextField(labelWithString: "Alert Sound:")
		soundLabel.frame = NSRect(x: 20, y: 56, width: 90, height: 20)
		content.addSubview(soundLabel)

		let soundPopup = NSPopUpButton(frame: NSRect(x: 115, y: 52, width: 160, height: 26))
		soundPopup.addItems(withTitles: alertSounds)
		soundPopup.selectItem(withTitle: selectedSound)
		soundPopup.target = self
		soundPopup.action = #selector(soundChanged(_:))
		content.addSubview(soundPopup)

		// Launch at login
		loginCheck = NSButton(checkboxWithTitle: "Launch at Login", target: self, action: #selector(loginToggled))
		loginCheck.frame = NSRect(x: 18, y: 20, width: 200, height: 20)
		content.addSubview(loginCheck)
	}

	// MARK: Settings actions

	@objc private func changeHotkey() {
		onChangeHotkey?()
	}

	@objc private func soundChanged(_ sender: NSPopUpButton) {
		guard let name = sender.titleOfSelectedItem else { return }
		onSelectSound?(name)
	}

	@objc private func loginToggled() {
		onToggleLaunchAtLogin?()
	}

	// MARK: Preset actions

	@objc private func addPreset() {
		statusLabel.stringValue = ""
		let preset = presetStore.add(total: 300)
		table.reloadData()
		guard let row = presetStore.presets.firstIndex(where: { $0.id == preset.id }) else { return }
		table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
		table.scrollRowToVisible(row)
		table.editColumn(0, row: row, with: nil, select: true)
	}

	@objc private func removePreset() {
		statusLabel.stringValue = ""
		let row = table.selectedRow
		guard row >= 0, row < presetStore.presets.count else { return }
		presetStore.remove(id: presetStore.presets[row].id)
		table.reloadData()
	}

	// MARK: Inline edit commit

	func controlTextDidEndEditing(_ obj: Notification) {
		guard let field = obj.object as? NSTextField else { return }
		let row = table.row(for: field)
		guard row >= 0, row < presetStore.presets.count else { return }
		let preset = presetStore.presets[row]

		if field.identifier?.rawValue == "label" {
			presetStore.update(id: preset.id, label: field.stringValue, total: preset.total)
			statusLabel.stringValue = ""
		} else {
			let text = field.stringValue.trimmingCharacters(in: .whitespaces)
			if let input = InputParser.parse(text), case .duration(let span) = input {
				presetStore.update(id: preset.id, label: preset.label, total: span)
				statusLabel.stringValue = ""
			} else {
				statusLabel.stringValue = text.isEmpty || InputParser.parse(text) == nil
					? "Can't read \"\(text)\" -- try 3m, 90s, 1h30m"
					: "Presets are durations only -- no clock times"
			}
		}

		// Re-render the row with canonical values (e.g. 90s -> 1m 30s);
		// async so tab-to-next-cell editing is not interrupted mid-flight
		DispatchQueue.main.async { [weak self] in
			guard let self, row < self.presetStore.presets.count else { return }
			self.table.reloadData(forRowIndexes: IndexSet(integer: row), columnIndexes: IndexSet([0, 1]))
		}
	}

	// MARK: NSTableViewDataSource

	func numberOfRows(in tableView: NSTableView) -> Int {
		presetStore.presets.count
	}

	// MARK: Drag to reorder

	func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
		let item = NSPasteboardItem()
		item.setString(String(row), forType: dragType)
		return item
	}

	func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo,
		proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation
	{
		dropOperation == .above ? .move : []
	}

	func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo,
		row: Int, dropOperation: NSTableView.DropOperation) -> Bool
	{
		guard let str = info.draggingPasteboard.pasteboardItems?.first?.string(forType: dragType),
			let from = Int(str)
		else { return false }
		presetStore.move(from: from, to: row)
		table.reloadData()
		let landed = from < row ? row - 1 : row
		table.selectRowIndexes(IndexSet(integer: landed), byExtendingSelection: false)
		return true
	}

	// MARK: NSTableViewDelegate

	func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
		let preset = presetStore.presets[row]
		let isLabel = tableColumn?.identifier.rawValue == "label"

		let field = NSTextField(string: isLabel ? (preset.label ?? "") : TimeFormat.compact(preset.total))
		field.identifier = tableColumn?.identifier
		field.isBordered = false
		field.drawsBackground = false
		field.isEditable = true
		field.font = .systemFont(ofSize: 13)
		field.lineBreakMode = .byTruncatingTail
		field.delegate = self
		if isLabel {
			field.placeholderString = "\(TimeFormat.compact(preset.total)) timer"
		}
		return field
	}
}
