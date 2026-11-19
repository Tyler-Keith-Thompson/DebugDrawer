#if DEBUG
    import Foundation

    /// Posts the system's memory warning to the app's observers. Its real default,
    /// ``MemoryWarningSimulator``, exists only on UIKit's platforms; the Mac has no memory warning,
    /// so its model takes none.
    @MainActor
    protocol MemoryWarningPoster {
        /// Posts the warning and returns when it was posted.
        func postMemoryWarning() -> Date
    }
#endif
