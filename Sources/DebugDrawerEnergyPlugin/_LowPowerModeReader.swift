#if DEBUG
    import Combine
    import Foundation

    /// Low Power Mode from `ProcessInfo`, with its change notification, which the system may post
    /// on any thread, delivered on the main queue.
    @MainActor
    final class _LowPowerModeReader: LowPowerModeReader {
        /// The notification's subscription while observing; `nil` otherwise.
        private var observation: AnyCancellable?

        var isLowPowerModeEnabled: Bool {
            ProcessInfo.processInfo.isLowPowerModeEnabled
        }

        func startObserving(_ change: @escaping @MainActor () -> Void) {
            observation = NotificationCenter.default
                .publisher(for: .NSProcessInfoPowerStateDidChange)
                .receive(on: DispatchQueue.main)
                .sink { _ in change() }
        }

        func stopObserving() {
            observation?.cancel()
            observation = nil
        }
    }
#endif
