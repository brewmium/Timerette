import Cocoa

// MARK: - AppDelegate

class AppDelegate: NSObject, NSApplicationDelegate {
	static weak var instance: AppDelegate?

	private var statusItem: NSStatusItem!

	// MARK: Lifecycle

	func applicationDidFinishLaunching(_ notification: Notification) {
		AppDelegate.instance = self
		setupMenuBar()
	}

	// MARK: Menu bar

	private func setupMenuBar() {
		statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
		if let button = statusItem.button {
			let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
			let icon = NSImage(systemSymbolName: "stopwatch", accessibilityDescription: "Timerette")!
				.withSymbolConfiguration(config)!
			icon.isTemplate = true
			button.image = icon
		}

		let menu = NSMenu()

		let quitItem = NSMenuItem(title: "Quit Timerette", action: #selector(quit), keyEquivalent: "")
		quitItem.target = self
		menu.addItem(quitItem)

		statusItem.menu = menu
	}

	// MARK: Actions

	@objc private func quit() {
		NSApp.terminate(nil)
	}
}
