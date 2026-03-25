import AppKit
import CoreGraphics

final class EventMonitor {
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    var onWordCaptured: ((String) -> Void)?

    func start() {
        guard AXIsProcessTrusted() else {
            print("[EventMonitor] Accessibility not granted — not starting")
            return
        }

        let mask = CGEventMask(1 << CGEventType.leftMouseUp.rawValue)

        tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { proxy, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon else { return Unmanaged.passRetained(event) }
                let monitor = Unmanaged<EventMonitor>.fromOpaque(refcon).takeUnretainedValue()
                monitor.handleEvent(event)
                return Unmanaged.passRetained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        guard let tap else {
            print("[EventMonitor] Failed to create event tap")
            return
        }

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        print("[EventMonitor] Started")
    }

    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let src = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes)
        }
        tap = nil
        runLoopSource = nil
    }

    private func handleEvent(_ event: CGEvent) {
        // Must be a double-click
        guard event.getIntegerValueField(.mouseEventClickState) == 2 else { return }
        // Must have Option key held
        guard event.flags.contains(.maskAlternate) else { return }

        // Re-enable tap if system disabled it
        if let tap, !CGEvent.tapIsEnabled(tap: tap) {
            CGEvent.tapEnable(tap: tap, enable: true)
        }

        // Dispatch word capture after a brief delay for selection to settle
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self else { return }
            TextCapture.captureSelectedText { word in
                guard let word else { return }
                self.onWordCaptured?(word)
            }
        }
    }

    deinit { stop() }
}
