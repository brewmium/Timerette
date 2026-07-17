import Cocoa
import Carbon.HIToolbox

// MARK: - Hotkey Recorder Panel

class HotKeyRecorderPanel: NSPanel {
	private let label: NSTextField
	private var keyMonitor: Any?
	var onRecord: ((UInt32, UInt32) -> Void)?

	init() {
		label = NSTextField(labelWithString: "Press a key combination...")

		super.init(
			contentRect: NSRect(x: 0, y: 0, width: 320, height: 100),
			styleMask: [.titled, .closable],
			backing: .buffered,
			defer: false
		)

		title = "Set Hotkey"
		level = .floating

		label.alignment = .center
		label.font = .systemFont(ofSize: 16)
		label.frame = NSRect(x: 20, y: 30, width: 280, height: 40)
		contentView?.addSubview(label)

		center()
	}

	func beginRecording() {
		makeKeyAndOrderFront(nil)
		NSApp.activate(ignoringOtherApps: true)

		keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
			guard let self = self else { return event }

			if event.keyCode == UInt16(kVK_Escape) {
				self.close()
				return nil
			}

			let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
			let hasModifier = mods.contains(.command) || mods.contains(.option)
				|| mods.contains(.control)

			guard hasModifier else {
				self.label.stringValue = "Need a modifier (\u{2318}, \u{2325}, \u{2303})"
				return nil
			}

			var carbonMods: UInt32 = 0
			if mods.contains(.command) { carbonMods |= UInt32(cmdKey) }
			if mods.contains(.option) { carbonMods |= UInt32(optionKey) }
			if mods.contains(.control) { carbonMods |= UInt32(controlKey) }
			if mods.contains(.shift) { carbonMods |= UInt32(shiftKey) }

			self.onRecord?(UInt32(event.keyCode), carbonMods)
			self.close()
			return nil
		}
	}

	override func close() {
		if let monitor = keyMonitor {
			NSEvent.removeMonitor(monitor)
			keyMonitor = nil
		}
		super.close()
	}
}
