import Cocoa
import Carbon.HIToolbox
import ServiceManagement
import UserNotifications

// MARK: - Carbon hotkey callback (free function for C interop)

private func hotKeyCallback(
	nextHandler: EventHandlerCallRef?,
	event: EventRef?,
	userData: UnsafeMutableRawPointer?
) -> OSStatus {
	AppDelegate.instance?.togglePanel()
	return noErr
}

// MARK: - AppDelegate

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, UNUserNotificationCenterDelegate {
	static weak var instance: AppDelegate?

	private var statusItem: NSStatusItem!
	private var entryPanel: TimerEntryPanel!
	private let timerStore = TimerStore()
	private let presetStore = PresetStore()
	private var hotKeyRef: EventHotKeyRef?
	private var eventHandlerRef: EventHandlerRef?
	private var runningMenuItems: [UUID: NSMenuItem] = [:]
	private var ringingSounds: [UUID: NSSound] = [:]
	private var chips: [UUID: AlertChip] = [:]
	private var notificationsAuthorized = false

	private static let alertSounds = [
		"Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero",
		"Morse", "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink",
	]
	private static let defaultAlertSound = "Glass"

	// MARK: Lifecycle

	func applicationDidFinishLaunching(_ notification: Notification) {
		AppDelegate.instance = self
		setupMenuBar()
		installEventHandler()
		registerHotKey()
		entryPanel = TimerEntryPanel()
		entryPanel.onStart = { [weak self] input, label in
			self?.timerStore.start(input, label: label)
		}
		entryPanel.presetsProvider = { [weak self] in
			self?.presetStore.presets ?? []
		}
		timerStore.onChange = { [weak self] in
			self?.renderStatusItem()
		}
		timerStore.onFire = { [weak self] timer in
			self?.timerFired(timer)
		}
		timerStore.onRingEnd = { [weak self] timer in
			self?.ringEnded(timer)
		}
		presetStore.onChange = { [weak self] in
			self?.entryPanel.refreshVisibleRows()
		}
		setupNotifications()
		renderStatusItem()
	}

	// MARK: Alerts on fire

	private var selectedAlertSound: String {
		UserDefaults.standard.string(forKey: "alertSound") ?? Self.defaultAlertSound
	}

	private func timerFired(_ timer: CountdownTimer) {
		// 10s chime loop (TimerStore ends the ring; any Stop cuts it early)
		if let sound = NSSound(named: selectedAlertSound) {
			sound.loops = true
			sound.play()
			ringingSounds[timer.id] = sound
		}

		postNotification(for: timer)

		// Guaranteed-visible rule: if you can't hear it, you can see it
		if AudioState.outputIsEffectivelySilent() || !notificationsAuthorized {
			showChip(for: timer)
		}
	}

	private func ringEnded(_ timer: CountdownTimer) {
		ringingSounds[timer.id]?.stop()
		ringingSounds[timer.id] = nil
		chips[timer.id]?.close()
		chips[timer.id] = nil
		UNUserNotificationCenter.current()
			.removeDeliveredNotifications(withIdentifiers: [timer.id.uuidString])
	}

	private func showChip(for timer: CountdownTimer) {
		let chip = AlertChip(timer: timer, index: chips.count)
		chip.onStop = { [weak self] id in
			self?.timerStore.stopRinging(id: id)
		}
		chips[timer.id] = chip
		chip.show()
	}

	// MARK: Notifications

	private func setupNotifications() {
		let center = UNUserNotificationCenter.current()
		center.delegate = self
		let stop = UNNotificationAction(identifier: "STOP", title: "Stop", options: [])
		let category = UNNotificationCategory(
			identifier: "TIMER_DONE", actions: [stop], intentIdentifiers: [], options: [])
		center.setNotificationCategories([category])
		center.requestAuthorization(options: [.alert]) { [weak self] granted, _ in
			DispatchQueue.main.async { self?.notificationsAuthorized = granted }
		}
	}

	private func postNotification(for timer: CountdownTimer) {
		guard notificationsAuthorized else { return }
		let content = UNMutableNotificationContent()
		content.title = timer.displayName
		content.body = "Time's up"
		content.categoryIdentifier = "TIMER_DONE"
		let request = UNNotificationRequest(
			identifier: timer.id.uuidString, content: content, trigger: nil)
		UNUserNotificationCenter.current().add(request)
	}

	// Show banners while the app is "frontmost" (accessory apps usually are not,
	// but a ringing timer must surface either way)
	func userNotificationCenter(_ center: UNUserNotificationCenter,
		willPresent notification: UNNotification,
		withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void)
	{
		completionHandler([.banner])
	}

	// Stop action -- or any click on the notification -- stops the ringing
	func userNotificationCenter(_ center: UNUserNotificationCenter,
		didReceive response: UNNotificationResponse,
		withCompletionHandler completionHandler: @escaping () -> Void)
	{
		if let id = UUID(uuidString: response.notification.request.identifier) {
			DispatchQueue.main.async { [weak self] in
				self?.timerStore.stopRinging(id: id)
			}
		}
		completionHandler()
	}

	// MARK: Menu bar

	private func renderStatusItem() {
		MenuBarView.render(statusItem: statusItem, store: timerStore)

		// Live-update running rows while the menu is open
		for (id, item) in runningMenuItems {
			if let timer = timerStore.timer(id: id) {
				item.title = runningTitle(timer)
			}
		}
	}

	private func setupMenuBar() {
		statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
		let menu = NSMenu()
		menu.delegate = self
		statusItem.menu = menu
	}

	// MARK: Menu building (rebuilt on every open)

	func menuNeedsUpdate(_ menu: NSMenu) {
		menu.removeAllItems()
		runningMenuItems = [:]

		// Running section
		if timerStore.count == 0 {
			menu.addItem(NSMenuItem(title: "No timers running", action: nil, keyEquivalent: ""))
		} else {
			for timer in timerStore.timers {
				let item = NSMenuItem(title: runningTitle(timer), action: nil, keyEquivalent: "")
				item.submenu = timerSubmenu(timer)
				menu.addItem(item)
				runningMenuItems[timer.id] = item
			}
		}
		menu.addItem(.separator())

		// Presets section
		let newTimerItem = NSMenuItem(title: "New Timer...", action: #selector(newTimer), keyEquivalent: "")
		newTimerItem.target = self
		applyHotkeyHint(to: newTimerItem)
		menu.addItem(newTimerItem)

		for preset in presetStore.presets {
			let title = preset.hasLabel
				? "\"\(preset.label!)\" (\(TimeFormat.compact(preset.total)))"
				: TimeFormat.compact(preset.total)
			let item = NSMenuItem(title: title, action: #selector(startPreset(_:)), keyEquivalent: "")
			item.target = self
			item.representedObject = preset.id
			menu.addItem(item)
		}

		menu.addItem(.separator())

		// Settings + quit
		let settingsItem = NSMenuItem(title: "Settings...", action: #selector(showSettings), keyEquivalent: "")
		settingsItem.target = self
		menu.addItem(settingsItem)

		let quitItem = NSMenuItem(title: "Quit Timerette", action: #selector(quit), keyEquivalent: "")
		quitItem.target = self
		menu.addItem(quitItem)
	}

	private func runningTitle(_ timer: CountdownTimer) -> String {
		switch timer.state {
		case .ringing: return "\(timer.displayName) -- Time's up"
		case .paused: return "\(timer.displayName) -- \(TimeFormat.compact(timer.remaining)) (paused)"
		case .running: return "\(timer.displayName) -- \(TimeFormat.compact(timer.remaining))"
		}
	}

	private func timerSubmenu(_ timer: CountdownTimer) -> NSMenu {
		let sub = NSMenu()

		func add(_ title: String, _ action: Selector) {
			let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
			item.target = self
			item.representedObject = timer.id
			sub.addItem(item)
		}

		switch timer.state {
		case .ringing:
			add("Stop", #selector(stopTimerRinging(_:)))
		case .paused:
			add("Resume", #selector(resumeTimer(_:)))
			add("+1m", #selector(addMinuteToTimer(_:)))
			if timer.kind == .durationTimer {
				add("Start Over", #selector(restartTimer(_:)))
			}
			add("Cancel", #selector(cancelTimer(_:)))
		case .running:
			add("Pause", #selector(pauseTimer(_:)))
			add("+1m", #selector(addMinuteToTimer(_:)))
			if timer.kind == .durationTimer {
				add("Start Over", #selector(restartTimer(_:)))
			}
			add("Cancel", #selector(cancelTimer(_:)))
		}
		return sub
	}

	// Show the global hotkey as the New Timer... shortcut hint when it maps
	// to a plain menu key equivalent
	private func applyHotkeyHint(to item: NSMenuItem) {
		let pref = loadHotKeyPreference()
		let name = Self.keyName(pref.keyCode)
		guard name.count == 1 else { return }
		item.keyEquivalent = name.lowercased()
		var mask: NSEvent.ModifierFlags = []
		if pref.modifiers & UInt32(cmdKey) != 0 { mask.insert(.command) }
		if pref.modifiers & UInt32(optionKey) != 0 { mask.insert(.option) }
		if pref.modifiers & UInt32(controlKey) != 0 { mask.insert(.control) }
		if pref.modifiers & UInt32(shiftKey) != 0 { mask.insert(.shift) }
		item.keyEquivalentModifierMask = mask
	}

	// MARK: Timer menu actions

	@objc private func pauseTimer(_ sender: NSMenuItem) {
		guard let id = sender.representedObject as? UUID else { return }
		timerStore.pause(id: id)
	}

	@objc private func resumeTimer(_ sender: NSMenuItem) {
		guard let id = sender.representedObject as? UUID else { return }
		timerStore.resume(id: id)
	}

	@objc private func addMinuteToTimer(_ sender: NSMenuItem) {
		guard let id = sender.representedObject as? UUID else { return }
		timerStore.addMinute(id: id)
	}

	@objc private func restartTimer(_ sender: NSMenuItem) {
		guard let id = sender.representedObject as? UUID else { return }
		timerStore.restart(id: id)
	}

	@objc private func cancelTimer(_ sender: NSMenuItem) {
		guard let id = sender.representedObject as? UUID else { return }
		timerStore.cancel(id: id)
	}

	@objc private func stopTimerRinging(_ sender: NSMenuItem) {
		guard let id = sender.representedObject as? UUID else { return }
		timerStore.stopRinging(id: id)
	}

	private func toggleLaunchAtLogin() {
		do {
			if SMAppService.mainApp.status == .enabled {
				try SMAppService.mainApp.unregister()
			} else {
				try SMAppService.mainApp.register()
			}
		} catch {
			NSLog("Timerette: Failed to toggle login item: \(error)")
		}
	}

	// MARK: Global hotkey

	private func installEventHandler() {
		var eventType = EventTypeSpec(
			eventClass: OSType(kEventClassKeyboard),
			eventKind: UInt32(kEventHotKeyPressed)
		)
		InstallEventHandler(
			GetEventDispatcherTarget(),
			hotKeyCallback,
			1,
			&eventType,
			nil,
			&eventHandlerRef
		)
	}

	private func registerHotKey() {
		let pref = loadHotKeyPreference()
		let hotKeyID = EventHotKeyID(signature: OSType(0x544D5254), id: 1)
		RegisterEventHotKey(
			pref.keyCode,
			pref.modifiers,
			hotKeyID,
			GetEventDispatcherTarget(),
			0,
			&hotKeyRef
		)
	}

	func togglePanel() {
		if entryPanel.isVisible {
			entryPanel.dismiss()
		} else {
			entryPanel.showPanel()
		}
	}

	// MARK: Hotkey preferences

	private func loadHotKeyPreference() -> (keyCode: UInt32, modifiers: UInt32) {
		let defaults = UserDefaults.standard
		let keyCode: UInt32
		let modifiers: UInt32
		if defaults.object(forKey: "hotKeyKeyCode") != nil {
			keyCode = UInt32(defaults.integer(forKey: "hotKeyKeyCode"))
			modifiers = UInt32(defaults.integer(forKey: "hotKeyModifiers"))
		} else {
			keyCode = UInt32(kVK_ANSI_T)
			modifiers = UInt32(controlKey | optionKey | cmdKey)
		}
		return (keyCode, modifiers)
	}

	private func saveHotKeyPreference(keyCode: UInt32, modifiers: UInt32) {
		UserDefaults.standard.set(Int(keyCode), forKey: "hotKeyKeyCode")
		UserDefaults.standard.set(Int(modifiers), forKey: "hotKeyModifiers")
	}

	private func updateHotKey(keyCode: UInt32, modifiers: UInt32) {
		if let ref = hotKeyRef {
			UnregisterEventHotKey(ref)
			hotKeyRef = nil
		}
		let hotKeyID = EventHotKeyID(signature: OSType(0x544D5254), id: 1)
		RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetEventDispatcherTarget(), 0, &hotKeyRef)
		saveHotKeyPreference(keyCode: keyCode, modifiers: modifiers)
		// Menu titles pick up the new binding on the next menuNeedsUpdate
	}

	// MARK: Hotkey display

	func hotkeyDisplayString(keyCode: UInt32, modifiers: UInt32) -> String {
		var s = ""
		if modifiers & UInt32(controlKey) != 0 { s += "\u{2303}" }
		if modifiers & UInt32(optionKey) != 0 { s += "\u{2325}" }
		if modifiers & UInt32(shiftKey) != 0 { s += "\u{21E7}" }
		if modifiers & UInt32(cmdKey) != 0 { s += "\u{2318}" }
		s += Self.keyName(keyCode)
		return s
	}

	private static let keyNames: [UInt32: String] = {
		var m: [UInt32: String] = [
			0x00: "A", 0x01: "S", 0x02: "D", 0x03: "F", 0x04: "H",
			0x05: "G", 0x06: "Z", 0x07: "X", 0x08: "C", 0x09: "V",
			0x0B: "B", 0x0C: "Q", 0x0D: "W", 0x0E: "E", 0x0F: "R",
			0x10: "Y", 0x11: "T", 0x12: "1", 0x13: "2", 0x14: "3",
			0x15: "4", 0x16: "6", 0x17: "5", 0x18: "=", 0x19: "9",
			0x1A: "7", 0x1B: "-", 0x1C: "8", 0x1D: "0", 0x1E: "]",
			0x1F: "O", 0x20: "U", 0x21: "[", 0x22: "I", 0x23: "P",
			0x25: "L", 0x26: "J", 0x27: "'", 0x28: "K", 0x29: ";",
			0x2A: "\\", 0x2B: ",", 0x2C: "/", 0x2D: "N", 0x2E: "M",
			0x2F: ".", 0x32: "`",
		]
		m[UInt32(kVK_Space)] = "Space"
		m[UInt32(kVK_Return)] = "\u{21A9}"
		m[UInt32(kVK_Tab)] = "\u{21E5}"
		m[UInt32(kVK_Delete)] = "\u{232B}"
		m[UInt32(kVK_ForwardDelete)] = "\u{2326}"
		m[UInt32(kVK_Escape)] = "\u{238B}"
		m[UInt32(kVK_UpArrow)] = "\u{2191}"
		m[UInt32(kVK_DownArrow)] = "\u{2193}"
		m[UInt32(kVK_LeftArrow)] = "\u{2190}"
		m[UInt32(kVK_RightArrow)] = "\u{2192}"
		m[UInt32(kVK_F1)] = "F1"; m[UInt32(kVK_F2)] = "F2"
		m[UInt32(kVK_F3)] = "F3"; m[UInt32(kVK_F4)] = "F4"
		m[UInt32(kVK_F5)] = "F5"; m[UInt32(kVK_F6)] = "F6"
		m[UInt32(kVK_F7)] = "F7"; m[UInt32(kVK_F8)] = "F8"
		m[UInt32(kVK_F9)] = "F9"; m[UInt32(kVK_F10)] = "F10"
		m[UInt32(kVK_F11)] = "F11"; m[UInt32(kVK_F12)] = "F12"
		return m
	}()

	private static func keyName(_ keyCode: UInt32) -> String {
		keyNames[keyCode] ?? "Key\(keyCode)"
	}

	// MARK: Actions

	@objc private func newTimer() {
		entryPanel.showPanel()
	}

	// Starts immediately, without the panel
	@objc private func startPreset(_ sender: NSMenuItem) {
		guard let id = sender.representedObject as? UUID,
			let preset = presetStore.presets.first(where: { $0.id == id })
		else { return }
		timerStore.start(.duration(preset.total), label: preset.label)
	}

	@objc private func showSettings() {
		let panel = SettingsPanel(
			presetStore: presetStore,
			alertSounds: Self.alertSounds,
			selectedSound: selectedAlertSound
		)
		panel.hotkeyDisplay = { [weak self] in
			guard let self else { return "" }
			let pref = self.loadHotKeyPreference()
			return self.hotkeyDisplayString(keyCode: pref.keyCode, modifiers: pref.modifiers)
		}
		panel.onChangeHotkey = { [weak self, weak panel] in
			let recorder = HotKeyRecorderPanel()
			recorder.onRecord = { keyCode, modifiers in
				self?.updateHotKey(keyCode: keyCode, modifiers: modifiers)
				panel?.refreshHotkeyDisplay()
			}
			recorder.beginRecording()
		}
		panel.onSelectSound = { name in
			UserDefaults.standard.set(name, forKey: "alertSound")
			NSSound(named: name)?.play()
		}
		panel.launchAtLoginIsOn = { SMAppService.mainApp.status == .enabled }
		panel.onToggleLaunchAtLogin = { [weak self] in self?.toggleLaunchAtLogin() }
		NSApp.activate(ignoringOtherApps: true)
		panel.makeKeyAndOrderFront(nil)
	}

	@objc private func quit() {
		NSApp.terminate(nil)
	}
}
