#if DEBUG
    // Filtered at ingest rather than capped per subsystem: a cap per subsystem still lets many
    // noisy subsystems together evict a quiet app, and gives each line a different horizon.

    /// Which captured lines the console keeps at all, before they take a place in its bounded
    /// buffer: Apple's frameworks log debug and info chatter at a rate that would otherwise evict
    /// every line of the app's own within seconds.
    ///
    /// A line is dropped when its level is debug or info and its subsystem is Apple's (it starts
    /// with `com.apple.`), unless ``includesSystemDebugLogs`` is set. The app's lines, stdout and
    /// stderr, and Apple's notice, error and fault lines are always kept.
    struct ConsoleIngestFilter: Equatable, Sendable {
        /// Whether Apple subsystems' debug and info lines are kept too.
        var includesSystemDebugLogs = false

        /// Whether the console keeps `line`.
        func keeps(_ line: LogLine) -> Bool {
            includesSystemDebugLogs || !(line.isFromSystem && line.isChatter)
        }
    }

    extension LogLine {
        /// Whether one of Apple's frameworks logged it, by its subsystem (`com.apple.UIKit`).
        fileprivate var isFromSystem: Bool {
            subsystem.hasPrefix("com.apple.")
        }

        /// Whether its level is one a framework logs routinely: debug or info.
        fileprivate var isChatter: Bool {
            level <= .info
        }
    }
#endif
