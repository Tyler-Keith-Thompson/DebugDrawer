#if DEBUG
    import SwiftUI

    // MARK: - Visibility

    extension DebugDrawer {
        /// Opens the key window's drawer if it is closed and closes it if it is open. The panel
        /// slides in and out unless the system reduces motion; nothing of the app's moves.
        public func toggle() {
            keyPresentation.isOpen.toggle()
        }

        /// Hides the HUD, and every open drawer unless `drawer` is false, runs `action` once that
        /// has rendered, then shows them again. For screenshots and anything else that needs a
        /// clean view.
        ///
        /// - Parameters:
        ///   - hidesDrawer: Whether to close the drawers too; each reopens afterwards if it was open.
        ///   - action: The work to do while they are hidden.
        public func performWhileHidden(drawer hidesDrawer: Bool = true, _ action: @escaping @MainActor () async -> Void) {
            let reopened = hidesDrawer ? presentations.filter(\.isOpen) : []
            let hidesHUD = !hudLayout.pinned.isEmpty
            guard !reopened.isEmpty || hidesHUD else {
                Task { await action() }
                return
            }

            // The completion runs once the hiding has rendered. A fade is no motion, so the HUD's
            // transaction animates even when the system reduces motion. The drawers are in windows
            // of their own, which a capture of the app's window leaves out, so the action needn't
            // wait for their panels to finish closing.
            withAnimation(Self.motion(.easeInOut(duration: 0.15)) ?? .linear(duration: 0.1)) {
                reopened.forEach { $0.isOpen = false }
                self.isHUDHidden = true
            } completion: { [weak self] in
                Task { @MainActor [weak self] in
                    await action()
                    reopened.forEach { $0.isOpen = true }
                    withAnimation(Self.motion(.easeInOut(duration: 0.25)) ?? .linear(duration: 0.1)) {
                        self?.isHUDHidden = false
                    }
                }
            }
        }

        /// `animation`, or none when the user asked the system to reduce motion. The drawer is not a
        /// view, so it reads the system setting rather than `\.accessibilityReduceMotion`.
        static func motion(_ animation: Animation) -> Animation? {
            debugDrawerSystemReduceMotion ? nil : animation
        }
    }
#endif
