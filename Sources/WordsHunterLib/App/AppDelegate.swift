import AppKit
import UserNotifications

public final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusBar = StatusBarController()
    private let eventMonitor = EventMonitor()
    private var setupWindowController: SetupWindowController?

    // Hold references to all active bubbles
    private var activeBubbles: [BubbleWindow] = []
    private var isMonitoring = false
    private var accessibilityPollTimer: Timer?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        installEditMenu()
        statusBar.setup()
        statusBar.onOpenVault = { [weak self] in self?.openVaultFolder() }
        statusBar.onPreferences = { [weak self] in self?.showSetupWindow() }

        // Warm up NLTagger to avoid first-capture latency (~200ms cold start)
        TextCapture.warmUp()

        // If the app has never been configured, check whether the OpenClaw plugin
        // already set a words directory via the shared discovery file.
        // Pre-fill AppSettings so the setup window shows the path — user still confirms.
        if AppSettings.shared.vaultPath.isEmpty, let discovered = DiscoveryFile.read() {
            AppSettings.shared.vaultPath = discovered.words_directory
            AppSettings.shared.wordFolder = discovered.words_folder.isEmpty ? "Words" : discovered.words_folder
            AppSettings.shared.useWordFolder = !discovered.words_folder.isEmpty
        }

        // Migrate template.md if it predates the variable system
        WordPageCreator.seedTemplateIfNeeded(vaultPath: AppSettings.shared.vaultPath)

        if AppSettings.shared.isSetupComplete {
            startMonitoringWhenTrusted()
        } else {
            showSetupWindow()
        }
    }

    /// Starts the event monitor immediately if Accessibility is already granted,
    /// otherwise prompts the user and polls until permission is granted.
    private func startMonitoringWhenTrusted() {
        if AXIsProcessTrusted() {
            startEventMonitor()
            return
        }
        // Show the system prompt
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true]
        AXIsProcessTrustedWithOptions(options)
        // Poll every second until permission arrives, then start
        accessibilityPollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            if AXIsProcessTrusted() {
                timer.invalidate()
                self.accessibilityPollTimer = nil
                self.startEventMonitor()
            }
        }
    }

    public func applicationWillTerminate(_ notification: Notification) {
        accessibilityPollTimer?.invalidate()
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
            SightingsFile.recordSighting(
                word: captured.lemma,
                sentence: "",
                channel: sourceApp,
                vaultPath: AppSettings.shared.vaultPath
            )
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
            content.body = "Words directory not found. Check Preferences."
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
