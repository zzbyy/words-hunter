import AppKit

final class StatusBarController {
    private var statusItem: NSStatusItem?
    var onOpenVault: (() -> Void)?
    var onPreferences: (() -> Void)?

    func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.title = "🎯"
            button.toolTip = "Words Hunter"
        }

        let menu = NSMenu()
        menu.addItem(withTitle: "Words Hunter", action: nil, keyEquivalent: "").isEnabled = false
        menu.addItem(.separator())
        menu.addItem(withTitle: "Open Vault Folder", action: #selector(openVault), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Preferences…", action: #selector(showPreferences), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Words Hunter", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        statusItem?.menu = menu
    }

    @objc private func openVault() {
        onOpenVault?()
    }

    @objc private func showPreferences() {
        onPreferences?()
    }
}
