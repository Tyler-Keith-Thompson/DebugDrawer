#if DEBUG
    /// One of the process's threads and how much of a CPU core it is using, as the Threads list
    /// shows it. `Codable`, as the model's snapshot carries the list.
    struct ThreadCPU: Codable, Hashable, Sendable, Identifiable {
        /// The thread's name: its pthread name, "Main Thread" for an unnamed main thread, or
        /// "Thread 0x…" with its ID for any other unnamed one.
        let name: String
        /// The system-wide unique ID of the thread, which `pthread_threadid_np` also reports.
        let threadID: UInt64
        /// The share of one core the thread is using, from 0 to 1: the scheduler's recent
        /// average, which `thread_info` reports.
        let cpuUsage: Double

        var id: UInt64 { threadID }

        /// The name the list shows for a thread.
        ///
        /// - Parameters:
        ///   - pthreadName: The name `pthread_getname_np` gave, empty for an unnamed thread or
        ///     `nil` when the thread has no pthread.
        ///   - threadID: The thread's system-wide ID.
        ///   - isMainThread: Whether it is the app's main thread, which is usually unnamed.
        /// - Returns: The pthread name when it has one; otherwise "Main Thread" or
        ///   "Thread 0x" and the ID in hexadecimal.
        static func name(pthreadName: String?, threadID: UInt64, isMainThread: Bool) -> String {
            if let pthreadName, !pthreadName.isEmpty { return pthreadName }
            return isMainThread ? "Main Thread" : "Thread 0x\(String(threadID, radix: 16))"
        }

        /// The threads busiest first; threads using the same share follow in name order, then
        /// ID order, so the list doesn't reshuffle between samples.
        ///
        /// - Complexity: O(*n* log *n*).
        static func ranked(_ threads: [ThreadCPU]) -> [ThreadCPU] {
            threads.sorted { lhs, rhs in
                if lhs.cpuUsage != rhs.cpuUsage { return lhs.cpuUsage > rhs.cpuUsage }
                if lhs.name != rhs.name { return lhs.name < rhs.name }
                return lhs.threadID < rhs.threadID
            }
        }
    }
#endif
