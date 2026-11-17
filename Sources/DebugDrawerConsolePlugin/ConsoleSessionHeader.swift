#if DEBUG
    import Foundation

    /// The first line of a session's file: which format the lines after it are in, when the
    /// session started, and which build of the app it was.
    ///
    /// A session file is JSON Lines: this header, then one ``ConsoleSessionLine`` per line, each
    /// log line as it was captured.
    struct ConsoleSessionHeader: Codable, Equatable {
        /// The format of the lines this header heads; a reader skips a file of a later one.
        static let currentFormat = 1

        /// ISO 8601 with milliseconds, in UTC: `2027-01-15T08:00:00.000Z`.
        static let dateStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

        /// The format of the lines after it, in the key that marks the line as a header.
        var format = Self.currentFormat
        /// When the session started, in ``dateStyle``.
        var started: String
        /// The app's name.
        var app: String
        /// The app's version and build, `1.4 (212)`; empty when the bundle names neither.
        var appVersion: String

        enum CodingKeys: String, CodingKey {
            case format = "debugDrawerConsoleSession"
            case started, app, appVersion
        }
    }

    extension ConsoleSessionHeader {
        /// The header of a session of the app `bundle` that started at `started`.
        init(started: Date, bundle: Bundle) {
            let info = bundle.infoDictionary ?? [:]
            let version = info["CFBundleShortVersionString"] as? String
            let build = info["CFBundleVersion"] as? String
            self.init(
                started: Self.dateStyle.format(started),
                app: info["CFBundleName"] as? String ?? ProcessInfo.processInfo.processName,
                appVersion: [version, build.map { "(\($0))" }].compactMap(\.self).joined(separator: " ")
            )
        }
    }
#endif
