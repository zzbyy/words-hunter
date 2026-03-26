import AppKit
import QuartzCore

final class BubbleWindow: NSPanel {

    init(word: String, near point: CGPoint) {
        let font = NSFont.systemFont(ofSize: 16, weight: .bold)
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let textSize = (word as NSString).size(withAttributes: attrs)
        
        let hPad: CGFloat = 20
        let vPad: CGFloat = 10
        let bubbleW = textSize.width + hPad * 2
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
            word: word
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

        if let sound = NSSound(named: "Pop") ?? NSSound(named: "Tink") {
            sound.play()
        }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)

        scheduleHide()
    }

    private func scheduleHide() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
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

    init(frame: NSRect, bubbleSize: CGSize, word: String) {
        self.word = word
        self.bubbleSize = bubbleSize
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = false
        layer?.backgroundColor = .clear // Crucial to prevent rectangular artifacts
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
        let gradient = NSGradient(
            colors: [
                NSColor(red: 0.05, green: 0.05, blue: 0.09, alpha: 0.98),
                NSColor(red: 0.08, green: 0.08, blue: 0.15, alpha: 0.98)
            ]
        )
        gradient?.draw(in: pillRect, angle: 90)
        NSGraphicsContext.current?.restoreGraphicsState()

        // 2. Draw Border
        NSColor(red: 0.23, green: 0.51, blue: 0.96, alpha: 0.3).setStroke()
        let border = NSBezierPath(roundedRect: pillRect.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
        border.lineWidth = 1
        border.stroke()

        // 3. Setup Layer Shadow Path (Prevents the rectangular shadow artifact)
        layer?.shadowPath = CGPath(roundedRect: pillRect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        layer?.shadowColor = NSColor(red: 0.23, green: 0.51, blue: 0.96, alpha: 0.25).cgColor
        layer?.shadowOffset = .zero
        layer?.shadowRadius = 15
        layer?.shadowOpacity = 1

        // 4. Draw Text
        let font = NSFont.systemFont(ofSize: 16, weight: .bold)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraphStyle,
            .kern: 0.2
        ]
        
        let textSize = (word as NSString).size(withAttributes: attrs)
        let textRect = NSRect(
            x: pillRect.origin.x + (pillRect.width - textSize.width) / 2,
            y: pillRect.origin.y + (pillRect.height - textSize.height) / 2 - 1,
            width: textSize.width,
            height: textSize.height
        )
        (word as NSString).draw(in: textRect, withAttributes: attrs)
    }
}