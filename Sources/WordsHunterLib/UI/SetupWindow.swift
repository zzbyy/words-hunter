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

    private let lookupEnabledToggle = NSButton(checkboxWithTitle: "Enable Auto-Lookup", target: nil, action: nil)

    // MW fallback controls
    private let mwApiKeyField: NSTextField = {
        let f = NSTextField()
        f.placeholderString = "Paste your Merriam-Webster key here (optional)"
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

    // The MW subsection and research note — shown when Auto-Lookup is on, hidden when off
    private let mwSection: NSStackView = {
        let s = NSStackView()
        s.orientation = .vertical
        s.alignment = .leading
        s.spacing = 6
        s.isHidden = true
        return s
    }()

    private let researchNote: NSTextField = {
        let f = NSTextField(wrappingLabelWithString:
            "💡 The real learning happens when you write your own definition — use the lookup as a starting scaffold.")
        f.textColor = .secondaryLabelColor
        f.font = NSFont.systemFont(ofSize: 11)
        f.isHidden = true
        return f
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
        mwApiKeyField.delegate = self

        buildUI()
        loadCurrentSettings()
        updateWordFolderState()
        updateLookupState()
        updateRetriesState()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        if let window = view.window {
            let size = view.fittingSize
            window.setContentSize(size)
            window.minSize = NSSize(width: size.width, height: size.height)
        }
    }

    // MARK: - Build UI

    private func buildUI() {
        let margin: CGFloat = 24
        let contentWidth: CGFloat = 420

        // ── Intro ──
        let introLabel = NSTextField(wrappingLabelWithString:
            "Words Hunter captures vocabulary words from any app while you read or code.")
        introLabel.font = NSFont.boldSystemFont(ofSize: 13)
        introLabel.preferredMaxLayoutWidth = contentWidth

        // ── Words Directory section ──
        let dirHeader = sectionHeader("Words Directory", width: contentWidth)

        let browseBtn = NSButton(title: "Browse…", target: self, action: #selector(browse))
        browseBtn.bezelStyle = .rounded
        browseBtn.setContentHuggingPriority(.required, for: .horizontal)
        browseBtn.setContentCompressionResistancePriority(.required, for: .horizontal)
        vaultPathField.setAccessibilityLabel("Words directory path")

        let pathRow = hstack([vaultPathField, browseBtn])
        NSLayoutConstraint.activate([pathRow.widthAnchor.constraint(equalToConstant: contentWidth)])

        let folderRow = hstack([spacer(16), wordFolderField])
        NSLayoutConstraint.activate([folderRow.widthAnchor.constraint(equalToConstant: contentWidth)])

        // ── Dictionary Lookup section ──
        let lookupHeader = sectionHeader("Dictionary Lookup", width: contentWidth)

        let lookupNote = NSTextField(wrappingLabelWithString:
            "When enabled, Words Hunter automatically looks up the captured word and fills in the glosses, example sentences, and collocations — ready for you when you open the page.")
        lookupNote.textColor = .secondaryLabelColor
        lookupNote.font = NSFont.systemFont(ofSize: 11)
        lookupNote.preferredMaxLayoutWidth = contentWidth

        // MW fallback subsection — always visible when Auto-Lookup is on
        let mwHeader = NSTextField(labelWithString: "Merriam-Webster API Key")
        mwHeader.font = NSFont.boldSystemFont(ofSize: 11)
        mwHeader.textColor = .secondaryLabelColor

        let mwNote = NSTextField(wrappingLabelWithString:
            "Adding a key gives Auto-Lookup a reliable fallback, making the experience more robust and fluent.")
        mwNote.textColor = .tertiaryLabelColor
        mwNote.font = NSFont.systemFont(ofSize: 11)
        mwNote.preferredMaxLayoutWidth = contentWidth

        mwApiKeyField.setAccessibilityLabel("Merriam-Webster API key")
        NSLayoutConstraint.activate([mwApiKeyField.widthAnchor.constraint(equalToConstant: contentWidth)])

        retriesValueLabel.setContentHuggingPriority(.required, for: .horizontal)
        retriesStepper.setAccessibilityLabel("Lookup retries")
        let retryRow = hstack([label("Max retries:"), retriesStepper, retriesValueLabel])

        for v: NSView in [mwHeader, mwNote, mwApiKeyField, linkButton, retryRow] {
            mwSection.addArrangedSubview(v)
        }
        mwSection.setCustomSpacing(3, after: mwHeader)
        mwSection.setCustomSpacing(8, after: mwNote)
        mwSection.setCustomSpacing(4, after: mwApiKeyField)

        researchNote.preferredMaxLayoutWidth = contentWidth

        // ── Outer stack ──
        let outerStack = NSStackView()
        outerStack.orientation = .vertical
        outerStack.alignment = .leading
        outerStack.spacing = 8
        outerStack.edgeInsets = NSEdgeInsets(top: margin, left: margin, bottom: margin, right: margin)
        outerStack.translatesAutoresizingMaskIntoConstraints = false

        let divider = makeSeparator(width: contentWidth)

        for v in [introLabel,
                  dirHeader, pathRow, useWordFolderToggle, folderRow,
                  lookupHeader, lookupNote, lookupEnabledToggle, mwSection, researchNote,
                  divider,
                  editTemplateBtn, statusLabel, startBtn] {
            outerStack.addArrangedSubview(v)
        }

        outerStack.setCustomSpacing(20, after: introLabel)
        outerStack.setCustomSpacing(8,  after: dirHeader)
        outerStack.setCustomSpacing(20, after: folderRow)
        outerStack.setCustomSpacing(8,  after: lookupHeader)
        outerStack.setCustomSpacing(10, after: lookupEnabledToggle)
        outerStack.setCustomSpacing(12, after: mwSection)
        outerStack.setCustomSpacing(20, after: researchNote)
        outerStack.setCustomSpacing(16, after: divider)
        outerStack.setCustomSpacing(6,  after: editTemplateBtn)

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
        mwSection.isHidden = !on
        researchNote.isHidden = !on
        updateRetriesState()
        if let window = view.window {
            let size = view.fittingSize
            window.setContentSize(size)
            window.minSize = NSSize(width: size.width, height: size.height)
        }
    }

    private func updateRetriesState() {
        let lookupOn = lookupEnabledToggle.state == .on
        let hasKey = !mwApiKeyField.stringValue.trimmingCharacters(in: apiKeyTrimSet).isEmpty
        let enabled = lookupOn && hasKey
        retriesStepper.isEnabled = enabled
        retriesValueLabel.textColor = enabled ? .labelColor : .tertiaryLabelColor
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

    /// Section title with an inline separator line extending to `width`.
    private func sectionHeader(_ title: String, width: CGFloat) -> NSView {
        let lbl = NSTextField(labelWithString: title)
        lbl.font = NSFont.boldSystemFont(ofSize: 13)
        lbl.setContentHuggingPriority(.required, for: .horizontal)

        let sep = NSBox()
        sep.boxType = .separator

        let stack = NSStackView(views: [lbl, sep])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        NSLayoutConstraint.activate([stack.widthAnchor.constraint(equalToConstant: width)])
        return stack
    }

    /// Full-width horizontal separator line.
    private func makeSeparator(width: CGFloat) -> NSBox {
        let sep = NSBox()
        sep.boxType = .separator
        NSLayoutConstraint.activate([sep.widthAnchor.constraint(equalToConstant: width)])
        return sep
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

// MARK: - NSTextFieldDelegate

extension SetupViewController: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        guard (obj.object as? NSTextField) === mwApiKeyField else { return }
        updateRetriesState()
    }
}
