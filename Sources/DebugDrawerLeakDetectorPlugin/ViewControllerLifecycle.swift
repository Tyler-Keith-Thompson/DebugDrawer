#if DEBUG
    import ObjectiveC

    #if os(macOS)
        import AppKit

        /// Tells the leak detector when one of the app's view controllers leaves the screen for
        /// good, through `viewDidDisappear`, exchanged for the drawer's own at install.
        @MainActor
        enum ViewControllerLifecycle {
            private static var onDismiss: (@MainActor (NSViewController) -> Void)?

            /// Calls `onDismiss` with each of the app's view controllers whose view leaves its
            /// window from now on. The first call exchanges `viewDidDisappear`; later ones change
            /// nothing.
            static func install(onDismiss: @escaping @MainActor (NSViewController) -> Void) {
                guard self.onDismiss == nil else { return }
                self.onDismiss = onDismiss
                guard let original = class_getInstanceMethod(NSViewController.self, #selector(NSViewController.viewDidDisappear)),
                      let replacement = class_getInstanceMethod(NSViewController.self, #selector(NSViewController.dd_leakDetectorViewDidDisappear))
                else { return }
                method_exchangeImplementations(original, replacement)
            }

            /// Whether `object`, a view controller, is off screen for good: neither it nor the container it is
            /// in is in a window or presented. AppKit has no flag for a dismissal, so this is all
            /// that tells one from a view hidden for a while, such as a tab not selected.
            static func isDetached(_ object: AnyObject) -> Bool {
                guard let root = (object as? NSViewController)?.outermostParent else { return false }
                return root.viewIfLoaded?.window == nil && root.presentingViewController == nil
            }

            fileprivate static func didDisappear(_ viewController: NSViewController) {
                guard ClassOrigin(of: type(of: viewController)) == .app else { return }
                onDismiss?(viewController)
            }
        }

        extension NSViewController {
            /// What `viewDidDisappear` runs once exchanged: the original, then the leak detector.
            @objc fileprivate func dd_leakDetectorViewDidDisappear() {
                // Exchanged, this name runs the original implementation.
                dd_leakDetectorViewDidDisappear()
                ViewControllerLifecycle.didDisappear(self)
            }

            /// The container this view controller is in, through every level, or itself.
            fileprivate var outermostParent: NSViewController {
                sequence(first: self, next: \.parent).reduce(self) { $1 }
            }
        }

    #elseif canImport(UIKit)
        import UIKit

        // UIKit's view controllers are the same on iOS, Mac Catalyst, tvOS and visionOS, and so is
        // how one is dismissed, so this path serves all of them.

        /// Tells the leak detector when one of the app's view controllers leaves the screen for
        /// good, through `viewDidDisappear(_:)`, exchanged for the drawer's own at install.
        @MainActor
        enum ViewControllerLifecycle {
            private static var onDismiss: (@MainActor (UIViewController) -> Void)?

            /// Calls `onDismiss` with each of the app's view controllers dismissed, or removed
            /// from its container, from now on, as it disappears. The first call exchanges
            /// `viewDidDisappear(_:)`; later ones change nothing.
            static func install(onDismiss: @escaping @MainActor (UIViewController) -> Void) {
                guard self.onDismiss == nil else { return }
                self.onDismiss = onDismiss
                let originalSelector = #selector(UIViewController.viewDidDisappear(_:))
                let replacementSelector = #selector(UIViewController.dd_leakDetectorViewDidDisappear(_:))
                guard let original = class_getInstanceMethod(UIViewController.self, originalSelector),
                      let replacement = class_getInstanceMethod(UIViewController.self, replacementSelector)
                else { return }
                method_exchangeImplementations(original, replacement)
            }

            /// Whether `object`, a view controller, is off screen for good: neither it nor the container it is
            /// in is in a window or presented, so it wasn't shown again since it was dismissed.
            static func isDetached(_ object: AnyObject) -> Bool {
                guard let root = (object as? UIViewController)?.outermostParent else { return false }
                return root.viewIfLoaded?.window == nil && root.presentingViewController == nil
            }

            fileprivate static func didDisappear(_ viewController: UIViewController) {
                guard viewController.isLeavingForGood, ClassOrigin(of: type(of: viewController)) == .app else { return }
                onDismiss?(viewController)
            }
        }

        extension UIViewController {
            /// What `viewDidDisappear(_:)` runs once exchanged: the original, then the leak detector.
            @objc fileprivate func dd_leakDetectorViewDidDisappear(_ animated: Bool) {
                // Exchanged, this name runs the original implementation.
                dd_leakDetectorViewDidDisappear(animated)
                ViewControllerLifecycle.didDisappear(self)
            }

            /// Whether this view controller, or a container it is in, is being dismissed or removed
            /// from its own container, rather than covered by another screen or a tab not selected.
            fileprivate var isLeavingForGood: Bool {
                sequence(first: self, next: \.parent).contains { $0.isBeingDismissed || $0.isMovingFromParent }
            }

            /// The container this view controller is in, through every level, or itself.
            fileprivate var outermostParent: UIViewController {
                sequence(first: self, next: \.parent).reduce(self) { $1 }
            }
        }
    #endif
#endif
