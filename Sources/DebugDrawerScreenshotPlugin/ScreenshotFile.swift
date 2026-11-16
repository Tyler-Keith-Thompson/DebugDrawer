#if DEBUG
    import Foundation

    /// Where a captured screenshot went when it was saved to a directory.
    enum ScreenshotFile: Equatable {
        /// Written to this file.
        case saved(URL)
        /// The directory refused the write (a sandboxed host can't write to the Desktop): the
        /// user has to pick a location, as `.fileExporter` lets them.
        case needsLocation

        /// Writes `png` as `filename` in `directory`.
        ///
        /// - Returns: `.saved` with the file's URL, or `.needsLocation` when the write was refused
        ///   for lack of permission.
        /// - Throws: Any other error writing throws, such as a directory that doesn't exist.
        static func save(
            _ png: Data,
            as filename: String,
            in directory: URL
        ) throws -> ScreenshotFile {
            let url = directory.appendingPathComponent(filename)
            do {
                try png.write(to: url)
                return .saved(url)
            } catch let error as CocoaError where error.code == .fileWriteNoPermission {
                // What the sandbox's refusal, and a read-only directory's, surface as.
                return .needsLocation
            }
        }
    }
#endif
