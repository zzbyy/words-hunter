import AppKit

protocol SetupWindowDelegate: AnyObject {
    func setupDidComplete()
}

final class SetupWindowController: NSWindowController {
    weak var setupDelegate: SetupWindowDelegate?

    convenience init() {
        // Initial size; auto-resizes to fittingSize in viewDidAppear
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 300),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to Words Hunter 🎯"
        window.center()
        window.isReleasedWhenClosed = false
        self.init(window: window)

        let vc = SetupViewController()
        vc.setupDelegate = self
        window.contentViewController = vc
    }
}

extension SetupWindowController: SetupViewControllerDelegate {
    func setupViewControllerDidComplete(_ vc: SetupViewController) {
        window?.close()
        setupDelegate?.setupDidComplete()
    }
}

// MARK: -

protocol SetupViewControllerDelegate: AnyObject {
    func setupViewControllerDidComplete(_ vc: SetupViewController)
}

final class SetupViewController: NSViewController {
    weak var setupDelegate: SetupViewControllerDelegate?

    // MARK: - Controls

    // Vault
    private let vaultPathField: NSTextField = {
        let f = NSTextField()
        f.placeholderString = "/Users/you/Documents/My Vault"
        f.bezelStyle = .roundedBezel
        return f
    }()

    // Word Location
    private let useWordFolderToggle: NSButton = {
        let b = NSButton(checkboxWithTitle: "Save in a subfolder", target: nil, action: nil)
        return b
    }()

    private let wordFolderField: NSTextField = {
        let f = NSTextField()
        f.placeholderString = "Words"
        f.bezelStyle = .roundedBezel
        return f
    }()

    // Dictionary Lookup
    private let lookupEnabledToggle: NSButton = {
        let b = NSButton(checkboxWithTitle: "Enable auto-lookup", target: nil, action: nil)
        return b
    }()

    private let mwApiKeyField: NSSecureTextField = {
        let f = NSSecureTextField()
        f.placeholderString = "Paste your Merriam-Webster key here"
        f.bezelStyle = .roundedBezel
        return f
    }()

    private let retriesStepper: NSStepper = {
        let s = NSStepper()
        s.minValue = 1
        s.maxValue = 5
        s.increment = 1
        s.valueWraps = false
        return s
    }()

    private let retriesLabel: NSTextField = {
        let f = NSTextField(labelWithString: "3")
        f.setContentHuggingPriority(.required, for: .horizontal)
        return f
    }()

    private lazy var linkButton: NSButton = {
        let title = NSAttributedString(string: "Get a free key at dictionaryapi.com ↗", attributes: [
            .foregroundColor: NSColor.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .font: NSFont.systemFont(ofSize: 11)
        ])
        let b = NSButton(title: "", target: self, action: #selector(openApiKeyLink))
        b.attributedTitle = title
        b.isBordered = false
        b.setButtonType(.momentaryPushIn)
        return b
    }()

    // Status + start
    private let statusLabel: NSTextField = {
        let f = NSTextField(labelWithString: "Requires Accessibility permission to detect Option+double-click.")
        f.textColor = .secondaryLabelColor
        f.font = NSFont.systemFont(ofSize: 11)
        f.maximumNumberOfLines = 0
        return f
    }()

    private lazy var startBtn: NSButton = {
        let b = NSButton(title: "Start Hunting 🎯", target: self, action: #selector(startHunting))
        b.bezelStyle = .rounded
        b.keyEquivalent = "\r"
        return b
    }()

    // MARK: - View lifecycle

    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
        loadCurrentSettings()
        updateWordFolderState(animated: false)
        updateLookupState(animated: false)
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        if let window = view.window {
            let fitting = view.fittingSize
            window.setContentSize(fitting)
            window.minSize = fitting
        }
    }

    // MARK: - Build UI

    private func buildUI() {
        // ── Intro label ──
        let introLabel = NSTextField(labelWithString:
            "Words Hunter captures vocabulary words from any app while you read or code.")
        introLabel.font = NSFont.boldSystemFont(ofSize: 13)
        introLabel.maximumNumberOfLines = 0

        // ── Vault box ──
        let vaultBox = makeBox(title: "Obsidian Vault")
        let browseBtn = NSButton(title: "Browse…", target: self, action: #selector(browse))
        browseBtn.bezelStyle = .rounded
        browseBtn.setContentHuggingPriority(.required, for: .horizontal)

        let vaultRow = NSStackView(views: [vaultPathField, browseBtn])
        vaultRow.orientation = .horizontal
        vaultRow.spacing = 8
        vaultRow.alignment = .centerY

        vaultPathField.setAccessibilityLabel("Obsidian vault folder path")
        vaultBox.contentView = makeInnerStack([vaultRow])

        // ── Word Location box ──
        let locationBox = makeBox(title: "Word Location")

        // Indent the wordFolderField 16pt with a container stack
        let indentSpacer = NSView()
        indentSpacer.setContentHuggingPriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([indentSpacer.widthAnchor.constraint(equalToConstant: 16)])

        let folderRow = NSStackView(views: [indentSpacer, wordFolderField])
        folderRow.orientation = .horizontal
        folderRow.spacing = 0
        folderRow.alignment = .centerY

        useWordFolderToggle.target = self
        useWordFolderToggle.action = #selector(wordFolderToggleChanged)

        locationBox.contentView = makeInnerStack([useWordFolderToggle, folderRow])

        // ── Dictionary Lookup box ──
        let lookupBox = makeBox(title: "Dictionary Lookup")

        // Curated doc text — appears ABOVE the toggle so users read it before deciding
        let docText = NSTextField(wrappingLabelWithString:
            """
            📖 Dictionary Lookup
            When enabled, Words Hunter quietly fetches a definition from Merriam-Webster \
            after capturing a word — you'll find it waiting in your Obsidian page.

            💡 Research shows that writing your own definition strengthens memory far more \
            than reading one. Use this as a starting scaffold — the learning happens when \
            you edit it, not when it appears.
            """)
        docText.textColor = .secondaryLabelColor
        docText.font = NSFont.systemFont(ofSize: 11)

        lookupEnabledToggle.target = self
        lookupEnabledToggle.action = #selector(lookupToggleChanged)

        // API key row
        let apiKeyLabel = NSTextField(labelWithString: "MW API Key:")
        apiKeyLabel.setContentHuggingPriority(.required, for: .horizontal)
        mwApiKeyField.setAccessibilityLabel("Merriam-Webster API key")

        let apiKeyRow = NSStackView(views: [apiKeyLabel, mwApiKeyField])
        apiKeyRow.orientation = .horizontal
        apiKeyRow.spacing = 8
        apiKeyRow.alignment = .centerY

        // Retries row
        let retriesTextLabel = NSTextField(labelWithString: "Max retries:")
        retriesTextLabel.setContentHuggingPriority(.required, for: .horizontal)

        retriesStepper.target = self
        retriesStepper.action = #selector(retriesStepperChanged)
        retriesStepper.setAccessibilityLabel("Lookup retries")

        let retriesRow = NSStackView(views: [retriesTextLabel, retriesStepper, retriesLabel])
        retriesRow.orientation = .horizontal
        retriesRow.spacing = 6
        retriesRow.alignment = .centerY

        lookupBox.contentView = makeInnerStack([
            docText,
            lookupEnabledToggle,
            apiKeyRow,
            retriesRow,
            linkButton
        ])

        // ── Outer stack ──
        let outerStack = NSStackView(views: [
            introLabel, vaultBox, locationBox, lookupBox, statusLabel, startBtn
        ])
        outerStack.orientation = .vertical
        outerStack.alignment = .leading
        outerStack.spacing = 12
        outerStack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        outerStack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(outerStack)
        NSLayoutConstraint.activate([
            outerStack.topAnchor.constraint(equalTo: view.topAnchor),
            outerStack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            outerStack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            outerStack.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            outerStack.widthAnchor.constraint(greaterThanOrEqualToConstant: 440)
        ])
    }

    // MARK: - Load settings

    private func loadCurrentSettings() {
        let s = AppSettings.shared
        if !s.vaultPath.isEmpty { vaultPathField.stringValue = s.vaultPath }
        // Re-opening from Preferences after initial setup: use a friendlier button label
        if s.isSetupComplete {
            startBtn.title = "Save Settings"
        }
        wordFolderField.stringValue = s.wordFolder
        useWordFolderToggle.state = s.useWordFolder ? .on : .off
        lookupEnabledToggle.state = s.lookupEnabled ? .on : .off
        mwApiKeyField.stringValue = s.mwApiKey
        retriesStepper.intValue = Int32(s.lookupRetries)
        retriesLabel.stringValue = "\(s.lookupRetries)"
    }

    // MARK: - Interaction state

    private func updateWordFolderState(animated: Bool) {
        let enabled = useWordFolderToggle.state == .on
        wordFolderField.isEnabled = enabled
    }

    private func updateLookupState(animated: Bool) {
        let enabled = lookupEnabledToggle.state == .on
        mwApiKeyField.isEnabled = enabled
        retriesStepper.isEnabled = enabled
        retriesLabel.isEnabled = enabled
        linkButton.isEnabled = enabled
        if enabled {
            mwApiKeyField.window?.makeFirstResponder(mwApiKeyField)
        }
    }

    // MARK: - Actions

    @objc private func browse() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select Vault"
        if panel.runModal() == .OK, let url = panel.url {
            vaultPathField.stringValue = url.path
        }
    }

    @objc private func wordFolderToggleChanged() {
        updateWordFolderState(animated: true)
    }

    @objc private func lookupToggleChanged() {
        updateLookupState(animated: true)
    }

    @objc private func retriesStepperChanged() {
        let val = Int(retriesStepper.intValue)
        retriesLabel.stringValue = "\(val)"
        retriesStepper.setAccessibilityLabel("Lookup retries, \(val)")
    }

    @objc private func openApiKeyLink() {
        NSWorkspace.shared.open(URL(string: "https://dictionaryapi.com/register")!)
    }

    @objc private func startHunting() {
        let vaultPath = vaultPathField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !vaultPath.isEmpty else {
            showAlert("Please select your Obsidian vault folder.")
            return
        }

        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: vaultPath, isDirectory: &isDir), isDir.boolValue else {
            showAlert("Vault folder not found. Please choose a valid folder.")
            return
        }

        let settings = AppSettings.shared
        settings.vaultPath = vaultPath
        settings.useWordFolder = useWordFolderToggle.state == .on
        settings.wordFolder = wordFolderField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Words"
            : wordFolderField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.lookupEnabled = lookupEnabledToggle.state == .on
        settings.mwApiKey = mwApiKeyField.stringValue
        settings.lookupRetries = Int(retriesStepper.intValue)
        settings.isSetupComplete = true

        setupDelegate?.setupViewControllerDidComplete(self)
    }

    private func showAlert(_ message: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.alertStyle = .warning
        alert.runModal()
    }

    // MARK: - Helpers

    private func makeBox(title: String) -> NSBox {
        let box = NSBox()
        box.boxType = .primary
        box.titlePosition = .atTop
        box.title = title
        box.titleFont = NSFont.boldSystemFont(ofSize: 11)
        box.contentViewMargins = NSSize(width: 12, height: 8)
        return box
    }

    private func makeInnerStack(_ views: [NSView]) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        return stack
    }
}
