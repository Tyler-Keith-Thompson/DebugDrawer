#if DEBUG
    import Foundation

    /// Where the plugin's last capture stands.
    enum ScreenshotStatus: Codable, Equatable, Sendable {
        /// Nothing under way and nothing to report.
        case ready
        /// A capture is under way.
        case capturing
        /// The last capture was written to the file at this path.
        case saved(path: String)
        /// The folder refused the write (a sandboxed host can't write to the Desktop): the user
        /// has to pick where the capture goes, under this file name.
        case needsLocation(filename: String)
        /// The last capture waits for the view to put it on the clipboard.
        case copying
        /// The view put the last capture on the clipboard.
        case copied
        /// The last capture, save or export failed.
        case failed(ScreenshotFailure)
    }
#endif
