#if DEBUG
    import Combine
    import Foundation

    /// The thermal state from `ProcessInfo`, with its change notification, which the system may
    /// post on any thread, delivered on the main queue.
    @MainActor
    final class _ThermalStateReader: ThermalStateReader {
        /// The notification's subscription while observing; `nil` otherwise.
        private var observation: AnyCancellable?

        var thermalState: ProcessInfo.ThermalState {
            ProcessInfo.processInfo.thermalState
        }

        func startObserving(_ change: @escaping @MainActor () -> Void) {
            observation = NotificationCenter.default
                .publisher(for: ProcessInfo.thermalStateDidChangeNotification)
                .receive(on: DispatchQueue.main)
                .sink { _ in change() }
        }

        func stopObserving() {
            observation?.cancel()
            observation = nil
        }
    }
#endif
