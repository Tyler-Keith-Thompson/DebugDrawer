#if DEBUG
    import DebugDrawer

    #if os(macOS)
        import AppKit
    #elseif os(iOS)
        import UIKit
    #endif

    // MARK: - Click indicator

    // Both platforms only observe: the event reaches the app unchanged, and the ripple is drawn in
    // the View Inspector's overlay window (ViewBorderController.showRipple), never in the app's.

    #if os(macOS)

        /// Click indicators through a local `NSEvent` monitor, which the switch starts and stops,
        /// that hands each mouse-down to `handler` and returns it unchanged.
        @MainActor
        final class ClickIndicatorMonitor {
            private let handler: @MainActor (NSEvent) -> Void
            private var monitor: Any?

            init(handler: @escaping @MainActor (NSEvent) -> Void) {
                self.handler = handler
            }

            func start() {
                guard monitor == nil else { return }
                monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                    // A local monitor runs on the main thread, where AppKit delivers events.
                    MainActor.assumeIsolated { self?.handler(event) }
                    return event
                }
            }

            func stop() {
                guard let monitor else { return }
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }

            isolated deinit {
                stop()
            }
        }

    #elseif os(iOS)

        /// Touch indicators through a `UIWindow.sendEvent(_:)` swizzle that observes touches and
        /// never consumes them. `installViewInspector()` installs it once; the swizzled method
        /// shows ripples only while ``ViewBorderController/isClickIndicatorEnabled`` is on.
        @MainActor
        enum ClickIndicatorMonitor {
            private static var isInstalled = false

            /// Swaps `UIWindow.sendEvent(_:)` for `dd_sendEvent(_:)`; later calls do nothing, so
            /// the swap is never undone.
            static func install() {
                guard !isInstalled else { return }
                isInstalled = true

                let original = #selector(UIWindow.sendEvent(_:))
                let swizzled = #selector(UIWindow.dd_sendEvent(_:))
                guard let originalMethod = class_getInstanceMethod(UIWindow.self, original),
                      let swizzledMethod = class_getInstanceMethod(UIWindow.self, swizzled)
                else { return }
                method_exchangeImplementations(originalMethod, swizzledMethod)
            }
        }

        extension UIWindow {
            // After the swap this selector names UIKit's sendEvent(_:), so the call forwards the
            // event unchanged. The swizzle stays installed while indicators are off, so the flag
            // decides whether anything is drawn; the ripple goes in the overlay window over this
            // window's scene, not in this window.
            @objc func dd_sendEvent(_ event: UIEvent) {
                dd_sendEvent(event)

                let controller = ViewBorderController.shared
                guard controller.isClickIndicatorEnabled, let touches = event.allTouches else { return }
                for touch in touches where touch.phase == .began {
                    controller.showRipple(at: touch.location(in: self), in: self)
                }
            }
        }

    #endif
#endif
