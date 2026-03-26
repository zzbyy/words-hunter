import AppKit
import QuartzCore

final class BubbleWindow: NSPanel {

    private let word: String
    private let cursorPoint: CGPoint
    private let pouchPoint: CGPoint
    private let captureState: CaptureState
    private let screenScale: CGFloat

    private let auraColors: [CGColor] = [
        CGColor(red: 1.0,  green: 0.42, blue: 0.62, alpha: 1), // pink   #FF6B9D
        CGColor(red: 1.0,  green: 0.70, blue: 0.28, alpha: 1), // amber  #FFB347
        CGColor(red: 0.31, green: 0.80, blue: 0.77, alpha: 1), // mint   #4ECDC4
        CGColor(red: 0.27, green: 0.72, blue: 0.82, alpha: 1), // sky    #45B7D1
    ]

    init(word: String, at cursorPoint: CGPoint, state: CaptureState) {
        self.word = word
        self.cursorPoint = cursorPoint
        self.captureState = state

        // Pouch lives at the top-right corner of whichever screen the cursor is on
        let cursorScreen = NSScreen.screens.first { $0.frame.contains(cursorPoint) }
            ?? NSScreen.main!
        self.pouchPoint = CGPoint(x: cursorScreen.frame.maxX - 44,
                                  y: cursorScreen.frame.maxY - 44)
        self.screenScale = cursorScreen.backingScaleFactor

        // Panel covers the bounding rect of cursor→pouch + 60pt padding on all sides
        let originX = min(cursorPoint.x, pouchPoint.x) - 60
        let originY = min(cursorPoint.y, pouchPoint.y) - 60
        let panelW  = abs(pouchPoint.x - cursorPoint.x) + 120
        let panelH  = abs(pouchPoint.y - cursorPoint.y) + 120

        super.init(
            contentRect: NSRect(x: originX, y: originY, width: panelW, height: panelH),
            styleMask:   [.borderless, .nonactivatingPanel],
            backing:     .buffered,
            defer:       false
        )

        isOpaque          = false
        backgroundColor   = .clear
        ignoresMouseEvents = true
        level             = .screenSaver
        hasShadow         = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentView?.wantsLayer = true
    }

    func showAndAnimate() {
        makeKeyAndOrderFront(nil)

        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            showFallbackBubble()
            return
        }

        guard let root = contentView?.layer else { return }

        let origin = frame.origin
        let cursor = CGPoint(x: cursorPoint.x - origin.x, y: cursorPoint.y - origin.y)
        let pouch  = CGPoint(x: pouchPoint.x  - origin.x, y: pouchPoint.y  - origin.y)
        let skipReel = hypot(cursor.x - pouch.x, cursor.y - pouch.y) < 80

        let t0 = CACurrentMediaTime()

        // ── Phase 1: Magic Aura (0–200ms) ──────────────────────────────────────
        addAuraBubbles(to: root, at: cursor, startTime: t0,
                       enhanced: captureState.streak >= 3)

        // ── Phase 2: Lasso Snap (150–450ms) ────────────────────────────────────
        let tagLayer   = makeWordTag(for: word, at: cursor)
        let lassoLayer = makeLassoRing(at: cursor, isRare: captureState.isRare)
        root.addSublayer(tagLayer)
        root.addSublayer(lassoLayer)
        animateLasso(lassoLayer, startTime: t0)
        animateSquash(tagLayer, startTime: t0)

        // Sound + haptic fire at the snap frame (350ms)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            NSSound(named: "Pop")?.play()
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment,
                                                              performanceTime: .now)
        }

        if skipReel {
            // Cursor is very close to pouch: burst in place, skip the reel
            addBurstCircles(to: root, at: cursor, startTime: t0 + 0.45)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.orderOut(nil)
            }
        } else {
            // ── Phase 3: Reel to Pouch (450–650ms) ─────────────────────────────
            let pouchLayer = makePouchLayer(at: pouch, scale: captureState.pouchScale)
            root.addSublayer(pouchLayer)
            animatePouchFadeIn(pouchLayer, startTime: t0 + 0.45)
            animateReel(tag: tagLayer, lasso: lassoLayer,
                        from: cursor, to: pouch, root: root, startTime: t0 + 0.45)

            // ── Phase 4: Bag Gulp (650–750ms) ───────────────────────────────────
            animateGulp(pouchLayer, at: pouch, root: root, startTime: t0 + 0.65)

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { [weak self] in
                self?.orderOut(nil)
            }
        }
    }

    // MARK: - Phase 1: Magic Aura

    private func addAuraBubbles(to root: CALayer, at center: CGPoint,
                                startTime: CFTimeInterval, enhanced: Bool) {
        let count = enhanced ? 8 : 5
        for i in 0..<count {
            let angle = Double(i) / Double(count) * 2 * .pi
            let r: CGFloat = enhanced ? 45 : 35
            let end = CGPoint(x: center.x + CGFloat(cos(angle)) * r,
                              y: center.y + CGFloat(sin(angle)) * r)

            let dot = CALayer()
            dot.bounds          = CGRect(x: 0, y: 0, width: 8, height: 8)
            dot.cornerRadius    = 4
            dot.backgroundColor = auraColors[i % auraColors.count]
            dot.position        = center
            dot.opacity         = 0
            root.addSublayer(dot)

            let move = CABasicAnimation(keyPath: "position")
            move.fromValue = NSValue(point: center)
            move.toValue   = NSValue(point: end)

            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values   = [0.0, 0.8, 0.0]
            fade.keyTimes = [0.0, 0.3, 1.0]

            let group = CAAnimationGroup()
            group.animations  = [move, fade]
            group.duration    = 0.2
            group.beginTime   = startTime
            group.fillMode    = .forwards
            group.isRemovedOnCompletion = false
            dot.add(group, forKey: "aura_\(i)")
        }
    }

    // MARK: - Phase 2: Word Tag

    private func makeWordTag(for word: String, at center: CGPoint) -> CALayer {
        let font  = NSFont.systemFont(ofSize: 14, weight: .semibold)
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let ts    = (word as NSString).size(withAttributes: attrs)
        let w     = ts.width + 24
        let h     = ts.height + 12

        let tag = CALayer()
        tag.bounds          = CGRect(x: 0, y: 0, width: w, height: h)
        tag.position        = center
        tag.cornerRadius    = h / 2
        tag.backgroundColor = CGColor(red: 0.1, green: 0.1, blue: 0.18, alpha: 0.96)
        tag.borderColor     = CGColor(red: 0.29, green: 0.29, blue: 1.0, alpha: 0.3)
        tag.borderWidth     = 1

        let text = CATextLayer()
        text.string         = word
        text.font           = font
        text.fontSize       = 14
        text.foregroundColor = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
        text.alignmentMode  = .center
        text.bounds         = CGRect(x: 0, y: 0, width: w, height: h)
        text.position       = CGPoint(x: w / 2, y: h / 2)
        text.contentsScale  = screenScale
        tag.addSublayer(text)

        return tag
    }

    // MARK: - Phase 2: Lasso Ring

    private func makeLassoRing(at center: CGPoint, isRare: Bool) -> CAShapeLayer {
        let r: CGFloat = isRare ? 40 : 30
        let lasso = CAShapeLayer()
        lasso.path        = CGPath(ellipseIn: CGRect(x: -r, y: -r, width: r * 2, height: r * 2),
                                   transform: nil)
        lasso.strokeColor = CGColor(red: 1.0, green: 0.70, blue: 0.28, alpha: 1) // amber
        lasso.fillColor   = .clear
        lasso.lineWidth   = 2.5
        lasso.strokeEnd   = 0
        lasso.position    = center
        return lasso
    }

    private func animateLasso(_ lasso: CAShapeLayer, startTime: CFTimeInterval) {
        // Draw ring: strokeEnd 0→1, 150–350ms
        let draw = CABasicAnimation(keyPath: "strokeEnd")
        draw.fromValue      = 0
        draw.toValue        = 1
        draw.duration       = 0.2
        draw.beginTime      = startTime + 0.15
        draw.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        draw.fillMode       = .forwards
        draw.isRemovedOnCompletion = false
        lasso.add(draw, forKey: "draw")

        // Snap: scale 1.0→0.6 over 80ms starting at 350ms
        let snap = CABasicAnimation(keyPath: "transform.scale")
        snap.fromValue      = 1.0
        snap.toValue        = 0.6
        snap.duration       = 0.08
        snap.beginTime      = startTime + 0.35
        snap.timingFunction = CAMediaTimingFunction(name: .easeIn)
        snap.fillMode       = .forwards
        snap.isRemovedOnCompletion = false
        lasso.add(snap, forKey: "snap")
    }

    private func animateSquash(_ tag: CALayer, startTime: CFTimeInterval) {
        // Squash phase: 100ms starting at 350ms
        let squash = CABasicAnimation(keyPath: "transform")
        squash.fromValue      = CATransform3DIdentity
        squash.toValue        = CATransform3DMakeScale(1.3, 0.7, 1)
        squash.duration       = 0.1
        squash.beginTime      = 0
        squash.timingFunction = CAMediaTimingFunction(name: .easeIn)

        // Spring-back: 150ms starting right after squash
        let spring = CASpringAnimation(keyPath: "transform")
        spring.fromValue       = CATransform3DMakeScale(1.3, 0.7, 1)
        spring.toValue         = CATransform3DIdentity
        spring.stiffness       = 300
        spring.damping         = 14
        spring.mass            = 1
        spring.initialVelocity = 0
        spring.duration        = 0.15
        spring.beginTime       = 0.1  // relative to group start

        let group = CAAnimationGroup()
        group.animations  = [squash, spring]
        group.duration    = 0.25  // 0.1s squash + 0.15s spring
        group.beginTime   = startTime + 0.35
        group.fillMode    = .forwards
        group.isRemovedOnCompletion = false
        tag.add(group, forKey: "squash")
    }

    // MARK: - Phase 3: Pouch Icon

    private func makePouchLayer(at position: CGPoint, scale: CGFloat) -> CALayer {
        let size: CGFloat = 28 * scale
        let pouch = CATextLayer()
        pouch.string        = "🎒"
        pouch.fontSize      = size * 0.85
        pouch.bounds        = CGRect(x: 0, y: 0, width: size, height: size)
        pouch.position      = position
        pouch.alignmentMode = .center
        pouch.contentsScale = screenScale
        pouch.opacity       = 0
        return pouch
    }

    private func animatePouchFadeIn(_ pouch: CALayer, startTime: CFTimeInterval) {
        let anim = CABasicAnimation(keyPath: "opacity")
        anim.fromValue  = 0
        anim.toValue    = 1
        anim.duration   = 0.1
        anim.beginTime  = startTime
        anim.fillMode   = .forwards
        anim.isRemovedOnCompletion = false
        pouch.add(anim, forKey: "fadeIn")
    }

    // MARK: - Phase 3: Reel

    private func animateReel(tag: CALayer, lasso: CAShapeLayer,
                             from cursor: CGPoint, to pouch: CGPoint,
                             root: CALayer, startTime: CFTimeInterval) {
        let dx  = pouch.x - cursor.x
        let dy  = pouch.y - cursor.y
        let cp1 = CGPoint(x: cursor.x + dx * 0.25, y: cursor.y + max(abs(dy) * 0.5, 80))
        let cp2 = CGPoint(x: pouch.x  - dx * 0.25, y: pouch.y  + max(abs(dy) * 0.3, 60))

        let path = CGMutablePath()
        path.move(to: cursor)
        path.addCurve(to: pouch, control1: cp1, control2: cp2)

        // Shrink tag and lasso to small "tag" size at Phase 3 start
        for layer in [tag, lasso as CALayer] {
            let shrink = CABasicAnimation(keyPath: "transform.scale")
            shrink.fromValue      = 1.0
            shrink.toValue        = 0.5
            shrink.duration       = 0.08
            shrink.beginTime      = startTime
            shrink.timingFunction = CAMediaTimingFunction(name: .easeIn)
            shrink.fillMode       = .forwards
            shrink.isRemovedOnCompletion = false
            layer.add(shrink, forKey: "shrink")
        }

        // Move tag along Bezier
        let tagReel = CAKeyframeAnimation(keyPath: "position")
        tagReel.path            = path
        tagReel.duration        = 0.2
        tagReel.beginTime       = startTime
        tagReel.calculationMode = .cubicPaced
        tagReel.fillMode        = .forwards
        tagReel.isRemovedOnCompletion = false
        tag.add(tagReel, forKey: "reel")

        // Move lasso along same path (separate animation instance)
        let lassoReel = CAKeyframeAnimation(keyPath: "position")
        lassoReel.path            = path
        lassoReel.duration        = 0.2
        lassoReel.beginTime       = startTime
        lassoReel.calculationMode = .cubicPaced
        lassoReel.fillMode        = .forwards
        lassoReel.isRemovedOnCompletion = false
        lasso.add(lassoReel, forKey: "reel")

        // Fade both out near the end of the reel
        for layer in [tag, lasso as CALayer] {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue  = 1
            fade.toValue    = 0
            fade.duration   = 0.08
            fade.beginTime  = startTime + 0.14
            fade.fillMode   = .forwards
            fade.isRemovedOnCompletion = false
            layer.add(fade, forKey: "fade")
        }

        // Sparkle trail: 3 gold dots along the Bezier path
        addSparkleTrail(to: root, from: cursor, cp1: cp1, cp2: cp2, to: pouch,
                        startTime: startTime)
    }

    private func addSparkleTrail(to root: CALayer,
                                 from p0: CGPoint, cp1: CGPoint, cp2: CGPoint, to p3: CGPoint,
                                 startTime: CFTimeInterval) {
        let gold = CGColor(red: 1.0, green: 0.84, blue: 0.0, alpha: 0.8)
        let ts: [CGFloat] = [0.25, 0.5, 0.75]

        for (i, t) in ts.enumerated() {
            let pos = cubicBezier(t: t, p0: p0, p1: cp1, p2: cp2, p3: p3)

            let dot = CALayer()
            dot.bounds          = CGRect(x: 0, y: 0, width: 8, height: 8)
            dot.cornerRadius    = 4
            dot.backgroundColor = gold
            dot.position        = pos
            dot.opacity         = 0.8
            root.addSublayer(dot)

            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue  = 0.8
            fade.toValue    = 0
            fade.duration   = 0.2
            fade.beginTime  = startTime + Double(i) * 0.05
            fade.fillMode   = .forwards
            fade.isRemovedOnCompletion = false
            dot.add(fade, forKey: "fade")
        }
    }

    private func cubicBezier(t: CGFloat, p0: CGPoint, p1: CGPoint,
                             p2: CGPoint, p3: CGPoint) -> CGPoint {
        let u = 1 - t
        return CGPoint(
            x: u*u*u*p0.x + 3*u*u*t*p1.x + 3*u*t*t*p2.x + t*t*t*p3.x,
            y: u*u*u*p0.y + 3*u*u*t*p1.y + 3*u*t*t*p2.y + t*t*t*p3.y
        )
    }

    // MARK: - Phase 4: Bag Gulp

    private func animateGulp(_ pouch: CALayer, at center: CGPoint,
                             root: CALayer, startTime: CFTimeInterval) {
        // Pouch bounces: spring from 1.3 down to 1.0
        let gulp = CASpringAnimation(keyPath: "transform.scale")
        gulp.fromValue       = 1.3
        gulp.toValue         = 1.0
        gulp.stiffness       = 300
        gulp.damping         = 12
        gulp.mass            = 1
        gulp.initialVelocity = 0
        gulp.duration        = 0.1
        gulp.beginTime       = startTime
        gulp.fillMode        = .forwards
        gulp.isRemovedOnCompletion = false
        pouch.add(gulp, forKey: "gulp")

        // Burst circles from the pouch position
        addBurstCircles(to: root, at: center, startTime: startTime)

        // Pouch fades out
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue  = 1
        fade.toValue    = 0
        fade.duration   = 0.2
        fade.beginTime  = startTime + 0.1
        fade.fillMode   = .forwards
        fade.isRemovedOnCompletion = false
        pouch.add(fade, forKey: "fade")
    }

    private func addBurstCircles(to root: CALayer, at center: CGPoint,
                                 startTime: CFTimeInterval) {
        for i in 0..<6 {
            let angle = Double(i) / 6.0 * 2 * .pi
            let end = CGPoint(x: center.x + CGFloat(cos(angle)) * 30,
                              y: center.y + CGFloat(sin(angle)) * 30)

            let dot = CALayer()
            dot.bounds          = CGRect(x: 0, y: 0, width: 6, height: 6)
            dot.cornerRadius    = 3
            dot.backgroundColor = auraColors[i % auraColors.count]
            dot.position        = center
            dot.opacity         = 0
            root.addSublayer(dot)

            let move = CABasicAnimation(keyPath: "position")
            move.fromValue = NSValue(point: center)
            move.toValue   = NSValue(point: end)

            let scale = CABasicAnimation(keyPath: "transform.scale")
            scale.fromValue = 1.0
            scale.toValue   = 0.1

            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0.8
            fade.toValue   = 0

            let group = CAAnimationGroup()
            group.animations = [move, scale, fade]
            group.duration   = 0.2
            group.beginTime  = startTime
            group.timingFunction = CAMediaTimingFunction(name: .easeOut)
            group.fillMode   = .forwards
            group.isRemovedOnCompletion = false
            dot.add(group, forKey: "burst_\(i)")
        }
    }

    // MARK: - Reduced-motion fallback

    private func showFallbackBubble() {
        guard let root = contentView?.layer else { return }

        let font  = NSFont.systemFont(ofSize: 14, weight: .semibold)
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let ts    = (word as NSString).size(withAttributes: attrs)
        let w     = ts.width + 32
        let h     = ts.height + 16

        let origin = frame.origin
        let pos    = CGPoint(x: cursorPoint.x - origin.x,
                             y: cursorPoint.y - origin.y + 20)

        let bubble = CALayer()
        bubble.bounds          = CGRect(x: 0, y: 0, width: w, height: h)
        bubble.position        = pos
        bubble.cornerRadius    = h / 2
        bubble.backgroundColor = CGColor(red: 0.1, green: 0.1, blue: 0.18, alpha: 0.96)
        bubble.opacity         = 0
        root.addSublayer(bubble)

        let text = CATextLayer()
        text.string          = word
        text.font            = font
        text.fontSize        = 14
        text.foregroundColor = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
        text.alignmentMode   = .center
        text.bounds          = CGRect(x: 0, y: 0, width: w, height: h)
        text.position        = CGPoint(x: w / 2, y: h / 2)
        text.contentsScale   = screenScale
        bubble.addSublayer(text)

        let fadeIn = CABasicAnimation(keyPath: "opacity")
        fadeIn.fromValue  = 0
        fadeIn.toValue    = 1
        fadeIn.duration   = 0.25
        fadeIn.beginTime  = CACurrentMediaTime()
        fadeIn.fillMode   = .forwards
        fadeIn.isRemovedOnCompletion = false
        bubble.add(fadeIn, forKey: "fadeIn")
        bubble.opacity = 1

        NSSound(named: "Pop")?.play()
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self, weak bubble] in
            guard let bubble else { return }
            let fadeOut = CABasicAnimation(keyPath: "opacity")
            fadeOut.fromValue  = 1
            fadeOut.toValue    = 0
            fadeOut.duration   = 0.3
            fadeOut.beginTime  = CACurrentMediaTime()
            fadeOut.fillMode   = .forwards
            fadeOut.isRemovedOnCompletion = false
            bubble.add(fadeOut, forKey: "fadeOut")
            bubble.opacity = 0
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.orderOut(nil)
            }
        }
    }
}
