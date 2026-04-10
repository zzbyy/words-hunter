import AppKit
import QuartzCore

enum BubbleStatus {
    case success
    case captured
}

final class BubbleWindow: NSPanel {
    private let status: BubbleStatus

    init(word: String, near point: CGPoint, status: BubbleStatus = .success) {
        self.status = status
        let font = NSFont.systemFont(ofSize: 16, weight: .bold)
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let textSize = (word as NSString).size(withAttributes: attrs)

        let hPad: CGFloat = 20
        let vPad: CGFloat = 10
        let iconWidth: CGFloat = 16
        let iconGap: CGFloat = 6
        let bubbleW = hPad + iconWidth + iconGap + textSize.width + hPad
        let bubbleH = textSize.height + vPad * 2

        // Add a margin for the shadow to prevent clipping and rectangular artifacts
        let shadowMargin: CGFloat = 30
        let totalW = bubbleW + shadowMargin * 2
        let totalH = bubbleH + shadowMargin * 2

        // Center the window over the point, offset upwards
        let screenX = point.x - totalW / 2
        let screenY = point.y + 12 - shadowMargin
        let frame = NSRect(x: screenX, y: screenY, width: totalW, height: totalH)

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
        hasShadow = false // We use layer shadows for better control
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // Pass the bubble size and shadow margin to the view
        let bubble = BubbleView(
            frame: NSRect(origin: .zero, size: frame.size),
            bubbleSize: CGSize(width: bubbleW, height: bubbleH),
            word: word,
            status: status
        )
        contentView = bubble
    }

    func showAndAnimate() {
        alphaValue = 0
        makeKeyAndOrderFront(nil)

        guard let layer = contentView?.layer else {
            alphaValue = 1
            scheduleHide()
            return
        }

        layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        layer.frame = contentView?.bounds ?? .zero

        let duration: TimeInterval = 0.35
        let timing = CAMediaTimingFunction(controlPoints: 0.34, 1.56, 0.64, 1)

        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 0.3
        scale.toValue = 1.0
        scale.duration = duration
        scale.timingFunction = timing

        let move = CABasicAnimation(keyPath: "transform.translation.y")
        move.fromValue = -20
        move.toValue = 0
        move.duration = duration
        move.timingFunction = timing

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = 0.2

        let group = CAAnimationGroup()
        group.animations = [scale, move, fade]
        group.duration = duration
        group.fillMode = .forwards
        group.isRemovedOnCompletion = false

        layer.add(group, forKey: "entrance")
        self.alphaValue = 1.0

        if status == .success {
            if let sound = NSSound(named: "Pop") ?? NSSound(named: "Tink") {
                sound.play()
            }
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        } else {
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        }

        scheduleHide()
    }

    private func scheduleHide() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let layer = self?.contentView?.layer else {
                self?.orderOut(nil)
                return
            }

            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)

                let exitScale = CABasicAnimation(keyPath: "transform.scale")
                exitScale.toValue = 0.8
                let exitMove = CABasicAnimation(keyPath: "transform.translation.y")
                exitMove.toValue = 10

                layer.add(exitScale, forKey: "exitScale")
                layer.add(exitMove, forKey: "exitMove")

                self?.animator().alphaValue = 0
            } completionHandler: {
                self?.orderOut(nil)
            }
        }
    }
}

private final class BubbleView: NSView {
    private let word: String
    private let bubbleSize: CGSize
    private let status: BubbleStatus

    private let iconWidth: CGFloat = 16
    private let iconGap: CGFloat = 6

    init(frame: NSRect, bubbleSize: CGSize, word: String, status: BubbleStatus) {
        self.word = word
        self.bubbleSize = bubbleSize
        self.status = status
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = false
        layer?.backgroundColor = .clear

        // Pre-compute pill geometry for reuse in draw and shadow setup
        let pillRect = NSRect(
            x: (bounds.width - bubbleSize.width) / 2,
            y: (bounds.height - bubbleSize.height) / 2,
            width: bubbleSize.width,
            height: bubbleSize.height
        )
        let radius = pillRect.height / 2

        // Setup shadow once (prevents rectangular artifact)
        layer?.shadowPath = CGPath(roundedRect: pillRect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        let shadowColor = status == .captured
            ? NSColor(red: 0.35, green: 0.35, blue: 0.35, alpha: 0.15)
            : NSColor(red: 0.23, green: 0.51, blue: 0.96, alpha: 0.25)
        layer?.shadowColor = shadowColor.cgColor
        layer?.shadowOffset = .zero
        layer?.shadowRadius = 15
        layer?.shadowOpacity = 1
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        // Calculate the centered pill rect within the larger window frame
        let pillRect = NSRect(
            x: (bounds.width - bubbleSize.width) / 2,
            y: (bounds.height - bubbleSize.height) / 2,
            width: bubbleSize.width,
            height: bubbleSize.height
        )
        let radius = pillRect.height / 2
        let path = NSBezierPath(roundedRect: pillRect, xRadius: radius, yRadius: radius)

        // 1. Draw Gradient Background
        NSGraphicsContext.current?.saveGraphicsState()
        path.addClip()
        let gradient: NSGradient?
        if status == .captured {
            gradient = NSGradient(colors: [
                NSColor(red: 0.12, green: 0.12, blue: 0.13, alpha: 0.98),
                NSColor(red: 0.09, green: 0.09, blue: 0.10, alpha: 0.98)
            ])
        } else {
            gradient = NSGradient(colors: [
                NSColor(red: 0.05, green: 0.05, blue: 0.09, alpha: 0.98),
                NSColor(red: 0.08, green: 0.08, blue: 0.15, alpha: 0.98)
            ])
        }
        gradient?.draw(in: pillRect, angle: 90)
        NSGraphicsContext.current?.restoreGraphicsState()

        // 2. Draw Border
        let borderColor: NSColor = status == .captured
            ? NSColor(red: 0.35, green: 0.35, blue: 0.35, alpha: 0.3)
            : NSColor(red: 0.23, green: 0.51, blue: 0.96, alpha: 0.3)
        borderColor.setStroke()
        let border = NSBezierPath(roundedRect: pillRect.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
        border.lineWidth = 1
        border.stroke()

        // 3. Draw icon + word together
        let font = NSFont.systemFont(ofSize: 16, weight: .bold)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center

        let textColor: NSColor = status == .captured
            ? NSColor(white: 0.55, alpha: 1)
            : .white

        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor,
            .paragraphStyle: paragraphStyle,
            .kern: 0.2
        ]

        let textSize = (word as NSString).size(withAttributes: attrs)
        let contentWidth = iconWidth + iconGap + textSize.width
        let contentX = pillRect.origin.x + (pillRect.width - contentWidth) / 2
        let centerY = pillRect.midY

        // Draw indicator icon
        let iconCenterX = contentX + iconWidth / 2
        if status == .success {
            // Checkmark (✓)
            let check = NSBezierPath()
            check.move(to: NSPoint(x: iconCenterX - 5, y: centerY + 1))
            check.line(to: NSPoint(x: iconCenterX - 1, y: centerY - 4))
            check.line(to: NSPoint(x: iconCenterX + 6, y: centerY + 5))
            check.lineWidth = 2.5
            check.lineCapStyle = .round
            check.lineJoinStyle = .round
            NSColor.white.setStroke()
            check.stroke()
        } else {
            // Double chevron (») — skip
            let strokeColor = NSColor(white: 0.55, alpha: 1)
            strokeColor.setStroke()
            let chevronH: CGFloat = 5
            for offset: CGFloat in [-3, 3] {
                let chev = NSBezierPath()
                chev.move(to: NSPoint(x: iconCenterX + offset - 3, y: centerY + chevronH))
                chev.line(to: NSPoint(x: iconCenterX + offset + 2, y: centerY))
                chev.line(to: NSPoint(x: iconCenterX + offset - 3, y: centerY - chevronH))
                chev.lineWidth = 2
                chev.lineCapStyle = .round
                chev.lineJoinStyle = .round
                chev.stroke()
            }
        }

        // Draw word text
        let textRect = NSRect(
            x: contentX + iconWidth + iconGap,
            y: pillRect.origin.y + (pillRect.height - textSize.height) / 2 - 1,
            width: textSize.width,
            height: textSize.height
        )
        (word as NSString).draw(in: textRect, withAttributes: attrs)
    }
}
