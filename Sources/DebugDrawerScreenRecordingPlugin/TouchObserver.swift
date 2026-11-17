#if DEBUG && os(iOS)
    import UIKit

    /// The fingers on the recorded windows, for the frames' touch indicators: a gesture recognizer
    /// on each window that watches every touch and never recognizes, so it takes nothing from the
    /// app's own controls and gestures. Added when a recording with touches starts and removed when
    /// it stops; nothing is swizzled.
    @MainActor
    final class TouchObserver {
        private var recognizers: [(window: UIWindow, recognizer: TouchWatchingRecognizer)] = []
        private var touches: [UITouch] = []

        /// Watches the touches on each of `windows`.
        init(windows: [UIWindow]) {
            for window in windows {
                let recognizer = TouchWatchingRecognizer { [weak self] touch, isDown in
                    self?.update(touch, isDown: isDown)
                }
                window.addGestureRecognizer(recognizer)
                recognizers.append((window, recognizer))
            }
        }

        /// Where each finger is now, in `view`'s coordinates.
        func locations(in view: UIView) -> [CGPoint] {
            touches.map { $0.location(in: view) }
        }

        /// Stops watching: removes the recognizers.
        func remove() {
            for (window, recognizer) in recognizers {
                window.removeGestureRecognizer(recognizer)
            }
            recognizers = []
            touches = []
        }

        private func update(_ touch: UITouch, isDown: Bool) {
            touches.removeAll { $0 === touch }
            if isDown { touches.append(touch) }
        }
    }

    /// A recognizer that reports each touch as it begins, moves and ends, and fails rather than
    /// recognize: it cancels, delays and prevents no other touch handling.
    private final class TouchWatchingRecognizer: UIGestureRecognizer {
        private let report: @MainActor (UITouch, Bool) -> Void

        init(report: @escaping @MainActor (UITouch, Bool) -> Void) {
            self.report = report
            super.init(target: nil, action: nil)
            cancelsTouchesInView = false
            delaysTouchesBegan = false
            delaysTouchesEnded = false
            requiresExclusiveTouchType = false
        }

        override func touchesBegan(_ touches: Set<UITouch>, with _: UIEvent) {
            for touch in touches {
                report(touch, true)
            }
        }

        override func touchesMoved(_ touches: Set<UITouch>, with _: UIEvent) {
            for touch in touches {
                report(touch, true)
            }
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
            finish(touches, with: event)
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
            finish(touches, with: event)
        }

        override func canPrevent(_: UIGestureRecognizer) -> Bool {
            false
        }

        override func canBePrevented(by _: UIGestureRecognizer) -> Bool {
            false
        }

        /// Reports the lifted touches; once no finger is left, fails, which resets the recognizer
        /// for the next touch.
        private func finish(_ touches: Set<UITouch>, with event: UIEvent) {
            for touch in touches {
                report(touch, false)
            }
            let remaining = (event.allTouches ?? []).filter { $0.phase != .ended && $0.phase != .cancelled && !touches.contains($0) }
            if remaining.isEmpty { state = .failed }
        }
    }
#endif
