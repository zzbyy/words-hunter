import AppKit
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusBar = StatusBarController()
    private let eventMonitor = EventMonitor()
    private var setupWindowController: SetupWindowController?

    // Hold references to all active bubbles
    private var activeBubbles: [BubbleWindow] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        requestAccessibilityIfNeeded()
        statusBar.setup()
        statusBar.onOpenVault = { [weak self] in self?.openVaultFolder() }
        statusBar.onPreferences = { [weak self] in self?.showSetupWindow() }

        if AppSettings.shared.isSetupComplete {
            startEventMonitor()
        } else {
            showSetupWindow()
        }
    }

    private func requestAccessibilityIfNeeded() {
        guard !AXIsProcessTrusted() else { return }
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true]
        AXIsProcessTrustedWithOptions(options)
    }

    private func startEventMonitor() {
        eventMonitor.onWordCaptured = { [weak self] word in
            self?.handleCapturedWord(word)
        }
        eventMonitor.start()
    }

    private func handleCapturedWord(_ word: String) {
        let result = WordPageCreator.createPage(for: word)
        switch result {
        case .created:
            showBubble(for: word)
        case .skipped:
            break // already exists, silent
        case .error(let message):
            // Check if vault is missing
            let settings = AppSettings.shared
            if !FileManager.default.fileExists(atPath: settings.vaultPath) {
                notifyVaultMissing()
            } else {
                print("[WordsHunter] Error creating page: \(message)")
            }
        }
    }

    private func showBubble(for word: String) {
        let mousePos = NSEvent.mouseLocation
        let bubble = BubbleWindow(word: word, near: mousePos)
        activeBubbles.append(bubble)
        bubble.showAndAnimate()

        // Clean up reference after animation completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            self?.activeBubbles.removeAll { $0 === bubble }
        }
    }

    private func notifyVaultMissing() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "Words Hunter"
            content.body = "Vault folder not found. Check Preferences."
            let request = UNNotificationRequest(
                identifier: "vault-missing",
                content: content,
                trigger: nil
            )
            center.add(request)
        }
    }

    private func showSetupWindow() {
        if setupWindowController == nil {
            let wc = SetupWindowController()
            wc.setupDelegate = self
            setupWindowController = wc
        }
        NSApp.activate(ignoringOtherApps: true)
        setupWindowController?.showWindow(nil)
        setupWindowController?.window?.makeKeyAndOrderFront(nil)
    }

    private func openVaultFolder() {
        guard let url = AppSettings.shared.wordsFolderURL else { return }
        NSWorkspace.shared.open(url)
    }
}

extension AppDelegate: SetupWindowDelegate {
    func setupDidComplete() {
        setupWindowController = nil
        startEventMonitor()
    }
}
