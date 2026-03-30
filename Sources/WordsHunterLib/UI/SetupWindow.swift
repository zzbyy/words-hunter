import AppKit

private let apiKeyTrimSet = CharacterSet.whitespacesAndNewlines
    .union(CharacterSet(charactersIn: "\"'`"))

protocol SetupWindowDelegate: AnyObject {
    func setupDidComplete()
}

final class SetupWindowController: NSWindowController {
    weak var setupDelegate: SetupWindowDelegate?

    convenience init() {
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

    private let vaultPathField: NSTextField = {
        let f = NSTextField()
        f.placeholderString = "/Users/you/Documents/English Words"
        f.bezelStyle = .roundedBezel
        return f
    }()

    private let useWordFolderToggle = NSButton(checkboxWithTitle: "Save captured words in a subfolder", target: nil, action: nil)

    private let wordFolderField: NSTextField = {
        let f = NSTextField()
        f.placeholderString = "Words"
        f.bezelStyle = .roundedBezel
        return f
    }()

    private let lookupEnabledToggle = NSButton(checkboxWithTitle: "Enable auto-lookup", target: nil, action: nil)

    private let mwApiKeyField: NSTextField = {
        let f = NSTextField()
        f.placeholderString = "Paste your Merriam-Webster key here"
        f.bezelStyle = .roundedBezel
        return f
    }()

    private let retriesStepper: NSStepper = {
        let s = NSStepper()
        s.minValue = 1; s.maxValue = 5; s.increment = 1; s.valueWraps = false
        return s
    }()

    private let retriesValueLabel = NSTextField(labelWithString: "3")

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

    private lazy var editTemplateBtn: NSButton = {
        let b = NSButton(title: "Edit Word Template…", target: self, action: #selector(editTemplate))
        b.bezelStyle = .rounded
        return b
    }()

    private let statusLabel: NSTextField = {
        let f = NSTextField(labelWithString:
            "Requires Accessibility permission to detect Option+double-click.")
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
        useWordFolderToggle.target = self
        useWordFolderToggle.action = #selector(wordFolderToggleChanged)
        lookupEnabledToggle.target = self
        lookupEnabledToggle.action = #selector(lookupToggleChanged)
        retriesStepper.target = self
        retriesStepper.action = #selector(retriesStepperChanged)

        buildUI()
        loadCurrentSettings()
        updateWordFolderState()
        updateLookupState()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        // Size window to exactly fit its content
        if let window = view.window {
            let size = view.fittingSize
            window.setContentSize(size)
            window.minSize = NSSize(width: size.width, height: size.height)
        }
    }

    // MARK: - Build UI

    private func buildUI() {
        let margin: CGFloat = 20
        let boxWidth: CGFloat = 440   // fixed reference width — box fills this

        // ── Intro label ──
        let introLabel = NSTextField(wrappingLabelWithString:
            "Words Hunter captures vocabulary words from any app while you read or code.")
        introLabel.font = NSFont.boldSystemFont(ofSize: 13)
        introLabel.preferredMaxLayoutWidth = boxWidth

        // ── Vault box ──
        let browseBtn = NSButton(title: "Browse…", target: self, action: #selector(browse))
        browseBtn.bezelStyle = .rounded
        browseBtn.setContentHuggingPriority(.required, for: .horizontal)
        browseBtn.setContentCompressionResistancePriority(.required, for: .horizontal)

        vaultPathField.setAccessibilityLabel("Words directory path")

        let vaultBox = makeBox(title: "Words Directory",
                               rows: [hstack([vaultPathField, browseBtn])],
                               width: boxWidth)

        // ── Word Location box ──
        // Indent the folder field 20pt with a leading spacer
        let folderRow = hstack([spacer(20), wordFolderField])
        let locationBox = makeBox(title: "Word Location",
                                  rows: [useWordFolderToggle, folderRow],
                                  width: boxWidth)

        // ── Dictionary Lookup box ──
        let docText = NSTextField(wrappingLabelWithString:
            """
            📖 Dictionary Lookup
            When enabled, Words Hunter quietly fetches a definition from Merriam-Webster \
            after capturing a word — you'll find it waiting in the word's page.

            💡 Research shows that writing your own definition strengthens memory far more \
            than reading one. Use this as a starting scaffold — the learning happens when \
            you edit it, not when it appears.
            """)
        docText.textColor = .secondaryLabelColor
        docText.font = NSFont.systemFont(ofSize: 11)
        docText.preferredMaxLayoutWidth = boxWidth - 24  // inset for box margins

        let apiKeyLabel = label("MW API Key:")
        mwApiKeyField.setAccessibilityLabel("Merriam-Webster API key")

        retriesValueLabel.setContentHuggingPriority(.required, for: .horizontal)
        retriesStepper.setAccessibilityLabel("Lookup retries")

        let lookupBox = makeBox(title: "Dictionary Lookup", rows: [
            docText,
            lookupEnabledToggle,
            hstack([apiKeyLabel, mwApiKeyField]),
            hstack([label("Max retries:"), retriesStepper, retriesValueLabel]),
            linkButton
        ], width: boxWidth)

        // ── Outer stack ──
        // Items pinned to the stack's width via matchWidth constraints added in makeBox.
        let outerStack = NSStackView()
        outerStack.orientation = .vertical
        outerStack.alignment = .leading
        outerStack.spacing = 12
        outerStack.edgeInsets = NSEdgeInsets(top: margin, left: margin,
                                             bottom: margin, right: margin)
        outerStack.translatesAutoresizingMaskIntoConstraints = false

        for v in [introLabel, vaultBox, locationBox, lookupBox, editTemplateBtn, statusLabel, startBtn] {
            outerStack.addArrangedSubview(v)
        }

        view.addSubview(outerStack)
        NSLayoutConstraint.activate([
            outerStack.topAnchor.constraint(equalTo: view.topAnchor),
            outerStack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            outerStack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            outerStack.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    // MARK: - Load settings

    private func loadCurrentSettings() {
        let s = AppSettings.shared
        if !s.vaultPath.isEmpty { vaultPathField.stringValue = s.vaultPath }
        wordFolderField.stringValue = s.wordFolder
        useWordFolderToggle.state = s.useWordFolder ? .on : .off
        lookupEnabledToggle.state = s.lookupEnabled ? .on : .off
        mwApiKeyField.stringValue = s.mwApiKey
        retriesStepper.intValue = Int32(s.lookupRetries)
        retriesValueLabel.stringValue = "\(s.lookupRetries)"
        if s.isSetupComplete { startBtn.title = "Save Settings" }
    }

    // MARK: - Interaction state

    private func updateWordFolderState() {
        wordFolderField.isEnabled = useWordFolderToggle.state == .on
    }

    private func updateLookupState() {
        let on = lookupEnabledToggle.state == .on
        linkButton.isEnabled = on
    }

    // MARK: - Actions

    @objc private func browse() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select Folder"
        if panel.runModal() == .OK, let url = panel.url {
            vaultPathField.stringValue = url.path
        }
    }

    @objc private func wordFolderToggleChanged() { updateWordFolderState() }
    @objc private func lookupToggleChanged()      { updateLookupState() }

    @objc private func retriesStepperChanged() {
        let val = Int(retriesStepper.intValue)
        retriesValueLabel.stringValue = "\(val)"
        retriesStepper.setAccessibilityLabel("Lookup retries, \(val)")
    }

    @objc private func openApiKeyLink() {
        NSWorkspace.shared.open(URL(string: "https://dictionaryapi.com/register/index.htm")!)
    }

    @objc private func editTemplate() {
        let vaultPath = vaultPathField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !vaultPath.isEmpty else { showAlert("Set your words directory first."); return }
        WordPageCreator.seedTemplateIfNeeded(vaultPath: vaultPath)
        let templateURL = URL(fileURLWithPath: vaultPath)
            .appendingPathComponent(".wordshunter")
            .appendingPathComponent("template.md")
        NSWorkspace.shared.open(templateURL)
    }

    @objc private func startHunting() {
        let vaultPath = vaultPathField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !vaultPath.isEmpty else { showAlert("Please select your words directory."); return }

        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: vaultPath, isDirectory: &isDir), isDir.boolValue else {
            showAlert("Directory not found. Please choose a valid folder.")
            return
        }

        let s = AppSettings.shared
        s.vaultPath = vaultPath
        s.useWordFolder = useWordFolderToggle.state == .on
        s.wordFolder = wordFolderField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty ? "Words" : wordFolderField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        s.lookupEnabled = lookupEnabledToggle.state == .on
        s.mwApiKey = mwApiKeyField.stringValue.trimmingCharacters(in: apiKeyTrimSet)
        s.lookupRetries = Int(retriesStepper.intValue)
        s.isSetupComplete = true
        s.exportConfigBridge()

        setupDelegate?.setupViewControllerDidComplete(self)
    }

    private func showAlert(_ message: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.alertStyle = .warning
        alert.runModal()
    }

    // MARK: - Layout helpers

    /// NSBox with a vertical stack of `rows` as its content, pinned to `width`.
    private func makeBox(title: String, rows: [NSView], width: CGFloat) -> NSBox {
        let box = NSBox()
        box.boxType = .primary
        box.titlePosition = .noTitle
        box.contentViewMargins = NSSize(width: 12, height: 10)

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = NSFont.boldSystemFont(ofSize: 11)

        let innerStack = NSStackView(views: [titleLabel] + rows)
        innerStack.orientation = .vertical
        innerStack.alignment = .leading
        innerStack.spacing = 8
        innerStack.translatesAutoresizingMaskIntoConstraints = false

        guard let cv = box.contentView else { return box }
        cv.addSubview(innerStack)
        NSLayoutConstraint.activate([
            innerStack.topAnchor.constraint(equalTo: cv.topAnchor),
            innerStack.leadingAnchor.constraint(equalTo: cv.leadingAnchor),
            innerStack.trailingAnchor.constraint(equalTo: cv.trailingAnchor),
            innerStack.bottomAnchor.constraint(equalTo: cv.bottomAnchor)
        ])

        NSLayoutConstraint.activate([
            box.widthAnchor.constraint(equalToConstant: width)
        ])
        return box
    }

    private func hstack(_ views: [NSView]) -> NSStackView {
        let s = NSStackView(views: views)
        s.orientation = .horizontal
        s.spacing = 8
        s.alignment = .centerY
        return s
    }

    private func label(_ text: String) -> NSTextField {
        let f = NSTextField(labelWithString: text)
        f.setContentHuggingPriority(.required, for: .horizontal)
        return f
    }

    private func spacer(_ width: CGFloat) -> NSView {
        let v = NSView()
        v.setContentHuggingPriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([v.widthAnchor.constraint(equalToConstant: width)])
        return v
    }
}

