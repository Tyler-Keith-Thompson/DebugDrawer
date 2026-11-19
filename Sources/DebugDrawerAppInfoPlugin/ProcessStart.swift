#if DEBUG
    import Foundation

    /// What the kernel knows about this process's start (`kinfo_proc`).
    struct ProcessStart: Codable, Equatable, Sendable {
        /// When the process started (`kp_proc.p_starttime`).
        var date: Date
        /// A debugger is attached (`P_TRACED` in `kp_proc.p_flag`).
        var isTraced: Bool

        static func current() -> ProcessStart? {
            var mib = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
            var info = kinfo_proc()
            var size = MemoryLayout<kinfo_proc>.size
            guard sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0) == 0 else { return nil }
            let start = info.kp_proc.p_starttime
            guard start.tv_sec > 0 else { return nil }
            return ProcessStart(
                date: Date(timeIntervalSince1970: TimeInterval(start.tv_sec) + TimeInterval(start.tv_usec) / 1_000_000),
                isTraced: info.kp_proc.p_flag & P_TRACED != 0
            )
        }
    }
#endif
