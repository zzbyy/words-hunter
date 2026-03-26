import AppKit
import UserNotifications

public final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusBar = StatusBarController()
    private let eventMonitor = EventMonitor()
    private var setupWindowController: SetupWindowController?

    // Hold references to all active bubbles
    private var activeBubbles: [BubbleWindow] = []
    private var isMonitoring = false

    public func applicationDidFinishLaunching(_ notification: Notification) {
        installEditMenu()
        requestAccessibilityIfNeeded()
        statusBar.setup()
        statusBar.onOpenVault = { [weak self] in self?.openVaultFolder() }
        statusBar.onPreferences = { [weak self] in self?.showSetupWindow() }

        // Warm up NLTagger to avoid first-capture latency (~200ms cold start)
        TextCapture.warmUp()

        if AppSettings.shared.isSetupComplete {
            startEventMonitor()
        } else {
            showSetupWindow()
        }
    }

    public func applicationWillTerminate(_ notification: Notification) {
        DictionaryService.shared.cancelAll()
    }

    private func installEditMenu() {
        let mainMenu = NSMenu()
        let editItem = NSMenuItem()
        editItem.submenu = {
            let m = NSMenu(title: "Edit")
            m.addItem(withTitle: "Undo",       action: Selector(("undo:")), keyEquivalent: "z")
            m.addItem(withTitle: "Redo",       action: Selector(("redo:")), keyEquivalent: "Z")
            m.addItem(.separator())
            m.addItem(withTitle: "Cut",        action: #selector(NSText.cut(_:)),       keyEquivalent: "x")
            m.addItem(withTitle: "Copy",       action: #selector(NSText.copy(_:)),      keyEquivalent: "c")
            m.addItem(withTitle: "Paste",      action: #selector(NSText.paste(_:)),     keyEquivalent: "v")
            m.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
            return m
        }()
        mainMenu.addItem(editItem)
        NSApp.mainMenu = mainMenu
    }

    private func requestAccessibilityIfNeeded() {
        guard !AXIsProcessTrusted() else { return }
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true]
        AXIsProcessTrustedWithOptions(options)
    }

    private func startEventMonitor() {
        guard !isMonitoring else { return }
        isMonitoring = true
        eventMonitor.onWordCaptured = { [weak self] captured in
            self?.handleCapturedWord(captured)
        }
        eventMonitor.start()
    }

    private func handleCapturedWord(_ captured: (word: String, lemma: String)) {
        let sourceApp = NSWorkspace.shared.frontmostApplication?.localizedName ?? "unknown"
        let result = WordPageCreator.createPage(lemma: captured.lemma, sourceApp: sourceApp)
        switch result {
        case .created(let path):
            showBubble(for: captured.word)
            let settings = AppSettings.shared
            if settings.lookupEnabled && !settings.mwApiKey.isEmpty {
                DictionaryService.shared.startLookup(word: captured.lemma, at: path)
            }
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
    public func setupDidComplete() {
        setupWindowController = nil
        startEventMonitor()
    }
}
