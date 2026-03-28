import AppKit
import QuartzCore

final class BubbleWindow: NSPanel {

    init(word: String, near point: CGPoint) {
        let font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let textSize = (word as NSString).size(withAttributes: attrs)

        let hPad: CGFloat = 20
        let vPad: CGFloat = 10
        let bubbleW = textSize.width + hPad * 2
        let bubbleH = textSize.height + vPad * 2

        // Center the window over the point, offset upwards
        let screenX = point.x - bubbleW / 2
        let screenY = point.y + 12
        let frame = NSRect(x: screenX, y: screenY, width: bubbleW, height: bubbleH)

        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        ignoresMouseEvents = true
        level = .floating
        hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let bubble = BubbleView(
            frame: NSRect(origin: .zero, size: frame.size),
            word: word
        )
        contentView = bubble
    }

    func showAndAnimate() {
        guard let screen = NSScreen.main else { return }
        _ = screen // suppress warning

        alphaValue = 0
        makeKeyAndOrderFront(nil)

        // Spring scale-in
        guard let layer = contentView?.layer else {
            alphaValue = 1
            scheduleHide()
            return
        }

        layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)

        let spring = CASpringAnimation(keyPath: "transform.scale")
        spring.mass = 1.0
        spring.stiffness = 200
        spring.damping = 15
        spring.initialVelocity = 0
        spring.fromValue = 0.01
        spring.toValue = 1.0
        spring.duration = spring.settlingDuration
        spring.isRemovedOnCompletion = false
        spring.fillMode = .forwards
        layer.add(spring, forKey: "scaleIn")

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().alphaValue = 1.0
        }

        // Play sound
        if let sound = NSSound(named: "Pop") ?? NSSound(named: "Tink") {
            sound.play()
        }

        // Haptic (best-effort — may be suppressed for background apps)
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)

        scheduleHide()
    }

    private func scheduleHide() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.3
                ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                self?.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                self?.orderOut(nil)
            })
        }
    }
}

private final class BubbleView: NSView {
    private let word: String

    init(frame: NSRect, word: String) {
        self.word = word
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let radius = bounds.height / 2

        // Gradient fill
        let path = NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius)
        path.addClip()

        let gradient = NSGradient(
            colors: [
                NSColor(calibratedRed: 0.1, green: 0.1, blue: 0.18, alpha: 0.96),
                NSColor(calibratedRed: 0.16, green: 0.16, blue: 0.31, alpha: 0.96)
            ]
        )
        gradient?.draw(in: bounds, angle: 90)

        // Subtle border
        NSColor(calibratedRed: 0.29, green: 0.29, blue: 1.0, alpha: 0.3).setStroke()
        let border = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
        border.lineWidth = 1
        border.stroke()

        // Glow shadow via layer
        layer?.shadowColor = NSColor(calibratedRed: 0.29, green: 0.29, blue: 1.0, alpha: 0.4).cgColor
        layer?.shadowOffset = .zero
        layer?.shadowRadius = 8
        layer?.shadowOpacity = 1

        // Word text
        let font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white
        ]
        let textSize = (word as NSString).size(withAttributes: attrs)
        let textRect = NSRect(
            x: (bounds.width - textSize.width) / 2,
            y: (bounds.height - textSize.height) / 2,
            width: textSize.width,
            height: textSize.height
        )
        (word as NSString).draw(in: textRect, withAttributes: attrs)
    }
}