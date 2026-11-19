#if DEBUG
    @testable import DebugDrawerScreenshotPlugin
    import Foundation

    /// A folder in memory: it keeps what it is asked to write, under its name, and answers with the
    /// outcome it is given, writing nothing to disk.
    final class FakeScreenshotSaver: ScreenshotSaver {
        /// Where a written file goes.
        private let folder: URL
        /// What a save does: write, refuse as the sandbox does, or fail.
        private let outcome: Result<Bool, ScreenshotFailure>
        /// Every file written, by name.
        private(set) var files: [String: Data] = [:]
        /// The names asked for, in order, whether written or not.
        private(set) var requests: [String] = []

        /// - Parameters:
        ///   - folder: Where a written file is said to be.
        ///   - outcome: `.success(true)` writes, `.success(false)` refuses so the user has to pick
        ///     a location, and a failure throws it.
        init(folder: URL = URL(fileURLWithPath: "/Users/dev/Desktop"), outcome: Result<Bool, ScreenshotFailure> = .success(true)) {
            self.folder = folder
            self.outcome = outcome
        }

        func save(_ png: Data, as filename: String) throws(ScreenshotFailure) -> ScreenshotFile {
            requests.append(filename)
            guard try outcome.get() else { return .needsLocation }
            files[filename] = png
            return .saved(folder.appendingPathComponent(filename))
        }
    }
#endif
