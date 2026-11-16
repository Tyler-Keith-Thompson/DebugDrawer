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
        /// A capture's filename: the app's name, `-Debug-`, the time in ISO 8601 with `-` for
        /// `:` (filesystems that reserve `:`), and `.png`.
        static func filename(appName: String, at date: Date) -> String {
            let timestamp = ISO8601DateFormatter().string(from: date).replacingOccurrences(of: ":", with: "-")
            return "\(appName)-Debug-\(timestamp).png"
        }

        /// The running app's name, from its bundle, or the process name when it has none.
        static var appName: String {
            Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? ProcessInfo.processInfo.processName
        }

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
