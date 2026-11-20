#if DEBUG
    import Combine
    @testable import DebugDrawerAppStateReset

    /// The app's foreground as the test says: in the background until it enters.
    @MainActor
    final class FakeForeground: AppForeground {
        private(set) var isInForeground: Bool
        private let entered = PassthroughSubject<Void, Never>()

        init(isInForeground: Bool = false) {
            self.isInForeground = isInForeground
        }

        var enteredForeground: AnyPublisher<Void, Never> {
            entered.eraseToAnyPublisher()
        }

        /// The app comes to the foreground, as the system's notification says.
        func enter() {
            isInForeground = true
            entered.send()
        }

        /// The app goes to the background.
        func leave() {
            isInForeground = false
        }
    }
#endif
