#if DEBUG
    import Foundation

    /// The process's start time from the kernel (`kinfo_proc.kp_proc.p_starttime`).
    struct _ProcessStartReader: ProcessStartReader {
        /// The process's start, converted from the wall clock to system uptime.
        func processStartUptime() -> TimeInterval? {
            guard let wallStart = processStartWallClock() else { return nil }
            // uptime now - (wall now - wall start) = uptime at process start
            let elapsed = Date().timeIntervalSince1970 - wallStart
            return ProcessInfo.processInfo.systemUptime - elapsed
        }

        /// The process's start time in seconds since 1970, or `nil` if the kernel didn't say.
        func processStartWallClock() -> TimeInterval? {
            var mib = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
            var info = kinfo_proc()
            var size = MemoryLayout<kinfo_proc>.size
            guard sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0) == 0 else { return nil }
            let start = info.kp_proc.p_starttime
            guard start.tv_sec > 0 else { return nil }
            return TimeInterval(start.tv_sec) + TimeInterval(start.tv_usec) / 1_000_000
        }
    }
#endif
