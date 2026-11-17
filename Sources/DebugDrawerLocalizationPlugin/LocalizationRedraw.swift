#if DEBUG
    import Combine

    /// Counts the changes of mode, which `debugLocalization()` gives its content's identity, so
    /// text drawn before a change is drawn again with it.
    @MainActor
    final class LocalizationRedraw: ObservableObject {
        /// The count the app's root view reads, for the life of the app.
        static let shared = LocalizationRedraw()

        /// How many times the mode has changed.
        @Published private(set) var generation = 0

        /// Counts a change of mode.
        func modeChanged() {
            generation += 1
        }
    }
#endif
