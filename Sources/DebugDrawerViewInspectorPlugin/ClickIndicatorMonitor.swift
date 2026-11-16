#if DEBUG
    import Combine
    import DebugDrawer
    import SwiftUI

    #if os(macOS)
    import AppKit
    #elseif os(iOS)
    import UIKit
    #endif

    // MARK: - Click indicator

    #if os(macOS)

    @MainActor
    final class ClickIndicatorMonitor {
        static let shared = ClickIndicatorMonitor()

        private var monitor: Any?
        private var overlayWindow: NSWindow?

        func start() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                self?.showRipple(for: event)
                return event
            }
        }

        func stop() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
            overlayWindow?.orderOut(nil)
            overlayWindow = nil
        }

        private func ensureOverlayWindow(for parentWindow: NSWindow) -> NSWindow {
            if let existing = overlayWindow, existing.parent == parentWindow {
                existing.setFrame(parentWindow.frame, display: false)
                return existing
            }
            overlayWindow?.orderOut(nil)

            let overlay = NSWindow(
                contentRect: parentWindow.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            overlay.isOpaque = false
            overlay.backgroundColor = .clear
            overlay.ignoresMouseEvents = true
            overlay.level = .floating
            overlay.hasShadow = false
            overlay.contentView = NSView(frame: parentWindow.frame)
            overlay.contentView?.wantsLayer = true

            parentWindow.addChildWindow(overlay, ordered: .above)
            overlayWindow = overlay
            return overlay
        }

        private func showRipple(for event: NSEvent) {
            guard let parentWindow = event.window else { return }
            let overlay = ensureOverlayWindow(for: parentWindow)
            guard let overlayContent = overlay.contentView else { return }

            // AppKit coordinates are bottom-left origin — no flip needed.
            let pointInWindow = event.locationInWindow
            let screenPoint = parentWindow.convertPoint(toScreen: pointInWindow)
            let overlayPoint = overlay.convertPoint(fromScreen: screenPoint)

            let size: CGFloat = 30
            let ripple = NSView(frame: NSRect(x: overlayPoint.x - size / 2, y: overlayPoint.y - size / 2, width: size, height: size))
            ripple.wantsLayer = true
            ripple.layer?.cornerRadius = size / 2
            ripple.layer?.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.4).cgColor
            ripple.layer?.borderWidth = 2
            ripple.layer?.borderColor = NSColor.systemBlue.withAlphaComponent(0.6).cgColor
            overlayContent.addSubview(ripple)

            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.4
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                ripple.animator().alphaValue = 0
                ripple.animator().frame = ripple.frame.insetBy(dx: -10, dy: -10)
            } completionHandler: {
                // AppKit calls the completion handler on the main thread.
                MainActor.assumeIsolated { ripple.removeFromSuperview() }
            }
        }
    }

    #elseif os(iOS)

    @MainActor
    /// Touch indicator via UIWindow.sendEvent swizzle — never intercepts touches.
    /// Matches DebugSwift's approach: observe touches, don't consume them.
    final class ClickIndicatorMonitor {
        static let shared = ClickIndicatorMonitor()

        private var swizzled = false

        func start() {
            guard !swizzled else { return }
            swizzled = true

            let original = #selector(UIWindow.sendEvent(_:))
            let swizzled = #selector(UIWindow.dd_sendEvent(_:))
            guard let originalMethod = class_getInstanceMethod(UIWindow.self, original),
                  let swizzledMethod = class_getInstanceMethod(UIWindow.self, swizzled)
            else { return }
            method_exchangeImplementations(originalMethod, swizzledMethod)
        }

        func stop() {
            // Swizzle is permanent — we check the enabled flag in the swizzled method
        }
    }

    extension UIWindow {
        @objc func dd_sendEvent(_ event: UIEvent) {
            // Call original
            dd_sendEvent(event)

            // Only show indicators when enabled
            guard ViewBorderController.shared.isClickIndicatorEnabled else { return }

            guard let touches = event.allTouches else { return }
            for touch in touches where touch.phase == .began {
                let point = touch.location(in: self)
                showTouchRipple(at: point)
            }
        }

        private func showTouchRipple(at point: CGPoint) {
            let size: CGFloat = 30
            let ripple = UIView(frame: CGRect(x: point.x - size / 2, y: point.y - size / 2, width: size, height: size))
            ripple.layer.cornerRadius = size / 2
            ripple.layer.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.4).cgColor
            ripple.layer.borderWidth = 2
            ripple.layer.borderColor = UIColor.systemBlue.withAlphaComponent(0.6).cgColor
            ripple.layer.zPosition = .greatestFiniteMagnitude
            ripple.isUserInteractionEnabled = false
            addSubview(ripple)

            UIView.animate(withDuration: 0.4, delay: 0, options: .curveEaseOut) {
                ripple.alpha = 0
                ripple.frame = ripple.frame.insetBy(dx: -10, dy: -10)
            } completion: { _ in
                ripple.removeFromSuperview()
            }
        }
    }

    #endif
#endif
