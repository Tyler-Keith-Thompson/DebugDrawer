#if DEBUG
    import Darwin
    import Foundation

    /// The file the crash handlers write as the app crashes, and the parser that reads it on the
    /// next launch.
    ///
    /// A line-based text format, because the signal handler can only `write(2)` bytes it already
    /// holds: a magic first line, then `key value` lines, and blocks of frame lines between a
    /// block keyword and `end`:
    ///
    /// ```
    /// DebugDrawer crash report 1
    /// app 1.2 (34)
    /// time 1763290000
    /// exception NSInvalidArgumentException
    /// reason *** -[__NSArrayI objectAtIndex:]: index 5 beyond bounds [0 .. 2]
    /// exception-frames
    /// 0   CoreFoundation   0x0000000180a0a2ec __exceptionPreprocess + 176
    /// end
    /// signal 6
    /// frames
    /// 0   libsystem_kernel.dylib   0x0000000180d5e5f0 __pthread_kill + 8
    /// end
    /// ```
    ///
    /// The exception handler writes the exception lines; the runtime then aborts, and the signal
    /// handler appends the signal lines to the same file. A handler that dies part way leaves a
    /// truncated file, which the parser reads as far as it goes.
    enum CrashFile {
        /// The file's name in the reports directory.
        static let name = "crash.txt"
        /// The first line of every crash file.
        static let magic = "DebugDrawer crash report 1"

        /// The report a crash file describes, or `nil` when `text` isn't a crash file or names
        /// neither a signal nor an exception.
        ///
        /// - Parameters:
        ///   - text: The file's contents.
        ///   - id: The new report's identity.
        ///   - fallbackDate: When the crash happened if the file doesn't say: the file's
        ///     modification date.
        static func parse(_ text: String, id: UUID, fallbackDate: Date) -> CrashReport? {
            var lines = text.split(separator: "\n", omittingEmptySubsequences: false)[...]
            guard lines.popFirst() == Substring(magic) else { return nil }
            var fields = Fields()
            while let line = lines.popFirst() {
                let (key, value) = line.keyAndValue
                switch key {
                case "app": fields.appVersion = value
                case "time": fields.time = TimeInterval(value)
                case "exception": fields.exception = value
                case "reason": fields.reasonLines.append(value)
                case "signal": fields.signal = Int32(value)
                case "exception-frames": fields.exceptionFrames = lines.popBlock()
                case "frames": fields.signalFrames = lines.popBlock()
                default: continue
                }
            }
            return fields.report(id: id, fallbackDate: fallbackDate)
        }

        /// The name and meaning of the signals the handler catches, by number.
        static func describe(signal: Int32) -> (name: String, meaning: String) {
            switch signal {
            case SIGABRT: ("SIGABRT", "Abort: the app called abort(), often after an uncaught exception or a failed assertion")
            case SIGSEGV: ("SIGSEGV", "Segmentation fault: an access to memory the app doesn't own")
            case SIGBUS: ("SIGBUS", "Bus error: an access to an address that can't be read")
            case SIGILL: ("SIGILL", "Illegal instruction")
            case SIGFPE: ("SIGFPE", "Arithmetic error, such as an integer divided by zero")
            case SIGTRAP: ("SIGTRAP", "Trap: a Swift runtime failure, such as unwrapping nil or an index out of range")
            default: ("Signal \(signal)", "Signal \(signal)")
            }
        }
    }

    /// What a crash file said, gathered line by line.
    private struct Fields {
        var appVersion: String?
        var time: TimeInterval?
        var exception: String?
        var reasonLines: [String] = []
        var signal: Int32?
        var exceptionFrames: [String] = []
        var signalFrames: [String] = []

        func report(id: UUID, fallbackDate: Date) -> CrashReport? {
            let title: String
            let reason: String?
            if let exception, !exception.isEmpty {
                title = exception
                reason = reasonLines.isEmpty ? nil : reasonLines.joined(separator: "\n")
            } else if let signal {
                let described = CrashFile.describe(signal: signal)
                title = described.name
                reason = described.meaning
            } else {
                return nil
            }
            return CrashReport(
                id: id,
                date: time.map(Date.init(timeIntervalSince1970:)) ?? fallbackDate,
                title: title,
                reason: reason,
                appVersion: appVersion.flatMap { $0.isEmpty ? nil : $0 },
                // An exception's own stack says where it was raised; the signal's is the abort
                // that followed.
                frames: exceptionFrames.isEmpty ? signalFrames : exceptionFrames,
                source: .captured,
                isSeen: false
            )
        }
    }

    extension Substring {
        /// The text before the first space, and the rest.
        fileprivate var keyAndValue: (key: Substring, value: String) {
            guard let space = firstIndex(of: " ") else { return (self, "") }
            return (self[..<space], String(self[index(after: space)...]))
        }
    }

    extension ArraySlice<Substring> {
        /// The lines up to `end`, dropping them and `end`; to the last line when `end` is missing.
        fileprivate mutating func popBlock() -> [String] {
            var block: [String] = []
            while let line = popFirst(), line != "end" {
                if !line.isEmpty { block.append(String(line)) }
            }
            return block
        }
    }
#endif
