import AppKit

protocol SetupWindowDelegate: AnyObject {
    func setupDidComplete()
}

final class SetupWindowController: NSWindowController {
    weak var setupDelegate: SetupWindowDelegate?

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 280),
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

protocol SetupViewControllerDelegate: AnyObject {
    func setupViewControllerDidComplete(_ vc: SetupViewController)
}

final class SetupViewController: NSViewController {
    weak var setupDelegate: SetupViewControllerDelegate?

    private let vaultPathField = NSTextField()
    private let wordFolderField = NSTextField()
    private let statusLabel = NSTextField()

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 460, height: 280))
        view.wantsLayer = true
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
        loadCurrentSettings()
    }

    private func buildUI() {
        // Title
        let title = makeLabel("Words Hunter captures vocabulary words from any app.", bold: true, size: 13)
        title.frame = NSRect(x: 24, y: 220, width: 412, height: 40)
        title.maximumNumberOfLines = 2

        // Vault Path
        let vaultLabel = makeLabel("Obsidian Vault Path:", bold: false, size: 12)
        vaultLabel.frame = NSRect(x: 24, y: 180, width: 140, height: 20)

        vaultPathField.frame = NSRect(x: 24, y: 156, width: 330, height: 24)
        vaultPathField.placeholderString = "/Users/you/Documents/My Vault"
        vaultPathField.bezelStyle = .roundedBezel

        let browseBtn = NSButton(title: "Browse", target: self, action: #selector(browse))
        browseBtn.frame = NSRect(x: 362, y: 156, width: 74, height: 24)
        browseBtn.bezelStyle = .rounded

        // Word Folder
        let folderLabel = makeLabel("Word Folder (inside vault):", bold: false, size: 12)
        folderLabel.frame = NSRect(x: 24, y: 120, width: 200, height: 20)

        wordFolderField.frame = NSRect(x: 24, y: 96, width: 200, height: 24)
        wordFolderField.placeholderString = "Words"
        wordFolderField.bezelStyle = .roundedBezel

        // Status label
        statusLabel.frame = NSRect(x: 24, y: 64, width: 412, height: 20)
        statusLabel.isEditable = false
        statusLabel.isBordered = false
        statusLabel.backgroundColor = .clear
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.font = NSFont.systemFont(ofSize: 11)
        statusLabel.stringValue = "Requires Accessibility permission to detect Option+double-click."

        // Start button
        let startBtn = NSButton(title: "Start Hunting 🎯", target: self, action: #selector(startHunting))
        startBtn.frame = NSRect(x: 24, y: 24, width: 160, height: 32)
        startBtn.bezelStyle = .rounded
        startBtn.keyEquivalent = "\r"

        [title, vaultLabel, vaultPathField, browseBtn, folderLabel,
         wordFolderField, statusLabel, startBtn].forEach { view.addSubview($0) }
    }

    private func loadCurrentSettings() {
        let s = AppSettings.shared
        if !s.vaultPath.isEmpty { vaultPathField.stringValue = s.vaultPath }
        if s.wordFolder != "Words" { wordFolderField.stringValue = s.wordFolder }
    }

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

    @objc private func startHunting() {
        let vaultPath = vaultPathField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let wordFolder = wordFolderField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

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
        settings.wordFolder = wordFolder.isEmpty ? "Words" : wordFolder
        settings.isSetupComplete = true

        setupDelegate?.setupViewControllerDidComplete(self)
    }

    private func showAlert(_ message: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.alertStyle = .warning
        alert.runModal()
    }

    private func makeLabel(_ text: String, bold: Bool, size: CGFloat) -> NSTextField {
        let f = NSTextField(labelWithString: text)
        f.font = bold ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size)
        f.isEditable = false
        f.isBordered = false
        f.backgroundColor = .clear
        return f
    }
}
