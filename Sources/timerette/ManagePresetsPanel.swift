import Cocoa

// MARK: - Manage Presets Panel

class ManagePresetsPanel: NSPanel, NSTableViewDataSource, NSTableViewDelegate {
	private let presetStore: PresetStore
	private var table: NSTableView!
	private let labelField = NSTextField()
	private let durationField = NSTextField()
	private let statusLabel = NSTextField(labelWithString: "")

	init(presetStore: PresetStore) {
		self.presetStore = presetStore

		super.init(
			contentRect: NSRect(x: 0, y: 0, width: 520, height: 380),
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
		let content = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 380))
		contentView = content

		// Table
		table = NSTableView()
		let labelCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("label"))
		labelCol.title = "Label"
		labelCol.width = 280
		table.addTableColumn(labelCol)
		let durCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("duration"))
		durCol.title = "Duration"
		durCol.width = 150
		table.addTableColumn(durCol)
		table.rowHeight = 22
		table.dataSource = self
		table.delegate = self

		let scroll = NSScrollView(frame: NSRect(x: 20, y: 130, width: 480, height: 230))
		scroll.documentView = table
		scroll.hasVerticalScroller = true
		scroll.autoresizingMask = [.width, .height]
		content.addSubview(scroll)

		// Edit fields
		let labelTitle = NSTextField(labelWithString: "Label:")
		labelTitle.frame = NSRect(x: 20, y: 96, width: 60, height: 20)
		content.addSubview(labelTitle)

		labelField.frame = NSRect(x: 85, y: 94, width: 200, height: 24)
		labelField.placeholderString = "Tea"
		content.addSubview(labelField)

		let durTitle = NSTextField(labelWithString: "Duration:")
		durTitle.frame = NSRect(x: 300, y: 96, width: 70, height: 20)
		content.addSubview(durTitle)

		durationField.frame = NSRect(x: 375, y: 94, width: 125, height: 24)
		durationField.placeholderString = "3m, 90s, 1h30m"
		content.addSubview(durationField)

		// Status line (parse errors)
		statusLabel.frame = NSRect(x: 20, y: 66, width: 480, height: 20)
		statusLabel.textColor = .systemRed
		statusLabel.font = .systemFont(ofSize: 12)
		content.addSubview(statusLabel)

		// Buttons
		let addBtn = NSButton(title: "Add", target: self, action: #selector(addPreset))
		addBtn.frame = NSRect(x: 20, y: 20, width: 90, height: 32)
		content.addSubview(addBtn)

		let updateBtn = NSButton(title: "Update", target: self, action: #selector(updatePreset))
		updateBtn.frame = NSRect(x: 115, y: 20, width: 90, height: 32)
		content.addSubview(updateBtn)

		let removeBtn = NSButton(title: "Remove", target: self, action: #selector(removePreset))
		removeBtn.frame = NSRect(x: 210, y: 20, width: 90, height: 32)
		content.addSubview(removeBtn)
	}

	// MARK: Input handling

	// Duration track only -- a clock-time entry is rejected here
	private func parsedDuration() -> TimeInterval? {
		guard let input = InputParser.parse(durationField.stringValue) else {
			statusLabel.stringValue = "Can't read that duration -- try 3m, 90s, 1h30m"
			return nil
		}
		guard case .duration(let span) = input else {
			statusLabel.stringValue = "Presets are durations only -- no clock times"
			return nil
		}
		return span
	}

	private func trimmedLabel() -> String? {
		let label = labelField.stringValue.trimmingCharacters(in: .whitespaces)
		guard !label.isEmpty else {
			statusLabel.stringValue = "Preset needs a label"
			return nil
		}
		return label
	}

	// MARK: Actions

	@objc private func addPreset() {
		statusLabel.stringValue = ""
		guard let label = trimmedLabel(), let total = parsedDuration() else { return }
		presetStore.add(label: label, total: total)
		table.reloadData()
		labelField.stringValue = ""
		durationField.stringValue = ""
	}

	@objc private func updatePreset() {
		statusLabel.stringValue = ""
		let row = table.selectedRow
		guard row >= 0, row < presetStore.presets.count else {
			statusLabel.stringValue = "Select a preset to update"
			return
		}
		guard let label = trimmedLabel(), let total = parsedDuration() else { return }
		presetStore.update(id: presetStore.presets[row].id, label: label, total: total)
		table.reloadData()
	}

	@objc private func removePreset() {
		statusLabel.stringValue = ""
		let row = table.selectedRow
		guard row >= 0, row < presetStore.presets.count else {
			statusLabel.stringValue = "Select a preset to remove"
			return
		}
		presetStore.remove(id: presetStore.presets[row].id)
		table.reloadData()
		labelField.stringValue = ""
		durationField.stringValue = ""
	}

	// MARK: NSTableViewDataSource

	func numberOfRows(in tableView: NSTableView) -> Int {
		presetStore.presets.count
	}

	// MARK: NSTableViewDelegate

	func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
		let preset = presetStore.presets[row]
		let text = tableColumn?.identifier.rawValue == "label"
			? preset.label
			: TimeFormat.compact(preset.total)
		let label = NSTextField(labelWithString: text)
		label.font = .systemFont(ofSize: 13)
		label.lineBreakMode = .byTruncatingTail
		return label
	}

	func tableViewSelectionDidChange(_ notification: Notification) {
		let row = table.selectedRow
		guard row >= 0, row < presetStore.presets.count else { return }
		let preset = presetStore.presets[row]
		labelField.stringValue = preset.label
		durationField.stringValue = TimeFormat.compact(preset.total)
		statusLabel.stringValue = ""
	}
}
