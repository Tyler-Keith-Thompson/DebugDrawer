#if DEBUG
    import Foundation

    /// A saved screen recording: a QuickTime movie in the recordings folder.
    struct Recording: Identifiable, Equatable, Sendable {
        /// The movie.
        let url: URL
        /// When the recording started.
        let started: Date
        /// How long it runs, or `nil` when the movie can't be read.
        let duration: Duration?
        /// The movie's size on disk.
        let byteCount: Int64

        /// The file's name, unique in the folder. The URL itself isn't the identity: the same file
        /// can be reached by more than one path (`/var` and `/private/var`).
        var id: String {
            url.lastPathComponent
        }

        /// Its length and size, as the list shows them: "0:12 · 3.4 MB", or the size alone when the
        /// length can't be read.
        var summary: String {
            let size = byteCount.formatted(.byteCount(style: .file))
            guard let duration else { return size }
            return "\(duration.recordingLength) · \(size)"
        }
    }

    extension Duration {
        /// Minutes and seconds ("0:12", "12:05"), and hours past the first ("1:02:03"); never
        /// negative.
        var recordingLength: String {
            let seconds = max(components.seconds, 0)
            let pattern: Duration.TimeFormatStyle.Pattern = seconds >= 3600 ? .hourMinuteSecond : .minuteSecond
            return Duration.seconds(seconds).formatted(.time(pattern: pattern))
        }
    }
#endif
