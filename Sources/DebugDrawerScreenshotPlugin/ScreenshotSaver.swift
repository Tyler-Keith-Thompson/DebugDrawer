#if DEBUG
    import Foundation

    /// Writes a capture where the developer finds it.
    ///
    /// The Screenshot model asks it on each save; `_ScreenshotSaver` writes to the Desktop, and a
    /// test passes one of its own.
    protocol ScreenshotSaver {
        /// Writes `png` as `filename`.
        ///
        /// - Returns: `.saved` with the file's URL, or `.needsLocation` when the folder refused the
        ///   write and the user has to pick one.
        /// - Throws: ``ScreenshotFailure/noDesktop`` when there is no folder to write to, and
        ///   ``ScreenshotFailure/writeFailed(_:)`` when the write fails otherwise.
        func save(_ png: Data, as filename: String) throws(ScreenshotFailure) -> ScreenshotFile
    }
#endif
