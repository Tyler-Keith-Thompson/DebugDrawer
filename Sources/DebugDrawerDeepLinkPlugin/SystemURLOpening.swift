#if DEBUG
    import Foundation

    /// Opens a URL as the system opens a tapped link, in whichever app takes its scheme.
    @MainActor
    protocol SystemURLOpening {
        /// Opens `url`, or throws why the system couldn't.
        func open(_ url: URL) async throws
    }
#endif
