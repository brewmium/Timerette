import Cocoa

// MARK: - Manage Presets Panel

// A plain editable list: click a cell and type -- edits commit when you
// leave the field (Return/Tab/click away), no separate save step. Drag rows
// to reorder. + adds a row, - removes the selected one. Labels are optional.
class ManagePresetsPanel: NSPanel, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
	private let presetStore: PresetStore
	private var table: NSTableView!
	private let statusLabel = NSTextField(labelWithString: "")
	private let dragType = NSPasteboard.PasteboardType("com.brewmium.timerette.preset-row")

	init(presetStore: PresetStore) {
		self.presetStore = presetStore

		super.init(
			contentRect: NSRect(x: 0, y: 0, width: 420, height: 360),
			styleMask: [.titled, .closable],
			backing: .buffered,
			defer: false
		)

		title = "Edit Presets"
		setupUI()
		table.reloadData()
		center()
	}

	private func setupUI() {
		let content = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 360))
		contentView = content

		// Table
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

		let scroll = NSScrollView(frame: NSRect(x: 20, y: 88, width: 380, height: 252))
		scroll.documentView = table
		scroll.hasVerticalScroller = true
		scroll.autoresizingMask = [.width, .height]
		content.addSubview(scroll)

		// Status line (parse errors)
		statusLabel.frame = NSRect(x: 20, y: 60, width: 380, height: 20)
		statusLabel.textColor = .systemRed
		statusLabel.font = .systemFont(ofSize: 12)
		content.addSubview(statusLabel)

		// Add / remove
		let addBtn = NSButton(title: "+", target: self, action: #selector(addPreset))
		addBtn.frame = NSRect(x: 20, y: 20, width: 32, height: 28)
		content.addSubview(addBtn)

		let removeBtn = NSButton(title: "-", target: self, action: #selector(removePreset))
		removeBtn.frame = NSRect(x: 56, y: 20, width: 32, height: 28)
		content.addSubview(removeBtn)

		let hint = NSTextField(labelWithString: "Click to edit. Drag to reorder. Labels are optional.")
		hint.textColor = .secondaryLabelColor
		hint.font = .systemFont(ofSize: 11)
		hint.frame = NSRect(x: 100, y: 24, width: 300, height: 17)
		content.addSubview(hint)
	}

	// MARK: Actions

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
