#if DEBUG
    import Foundation

    /// Why a capture, a save or an export failed. The view words each one.
    enum ScreenshotFailure: Error, Codable, Equatable, Sendable {
        /// The app has no key window to capture.
        case noWindow
        /// The window drew, but not into a PNG.
        case encodingFailed
        /// The user's Desktop folder couldn't be found.
        case noDesktop
        /// Writing the file failed, for the reason given.
        case writeFailed(String)
        /// The location the user picked refused the file, for the reason given.
        case exportFailed(String)
    }
#endif
