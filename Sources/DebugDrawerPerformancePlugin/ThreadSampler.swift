#if DEBUG
    import Darwin
    import Foundation

    /// Reads the process's threads and the CPU each is using. Tests of the views pass a fixed
    /// list instead.
    protocol ThreadSampler {
        /// The process's threads now, busiest first.
        func sample() -> [ThreadCPU]
    }

    /// The production sampler: the task's threads from Mach (`task_threads`), each one's CPU
    /// (`THREAD_BASIC_INFO`) and ID (`THREAD_IDENTIFIER_INFO`), and its name from its pthread
    /// (`pthread_from_mach_thread_np`, `pthread_getname_np`). All of them are public SDK calls.
    struct MachThreadSampler: ThreadSampler, Sendable {
        /// The main thread's ID, which names the main thread when it has no name of its own.
        let mainThreadID: UInt64

        /// The calling thread's system-wide ID; the monitor reads it on the main thread.
        static func currentThreadID() -> UInt64 {
            var id: UInt64 = 0
            pthread_threadid_np(nil, &id)
            return id
        }

        func sample() -> [ThreadCPU] {
            // The Energy plugin's processCPUUsage() walks the same list for its total. The few
            // lines are repeated here rather than shared: plugins share no helper target.
            var threadList: thread_act_array_t?
            var threadCount: mach_msg_type_number_t = 0
            guard task_threads(mach_task_self_, &threadList, &threadCount) == KERN_SUCCESS, let threads = threadList else { return [] }
            defer {
                vm_deallocate(mach_task_self_, vm_address_t(bitPattern: threads), vm_size_t(Int(threadCount) * MemoryLayout<thread_act_t>.size))
            }

            var sampled: [ThreadCPU] = []
            sampled.reserveCapacity(Int(threadCount))
            for index in 0 ..< Int(threadCount) {
                let thread = threads[index]
                if let row = describe(thread) { sampled.append(row) }
                // task_threads hands over a send right on each thread; release it.
                mach_port_deallocate(mach_task_self_, thread)
            }
            return ThreadCPU.ranked(sampled)
        }

        /// One thread's row, or `nil` when it ended between the listing and the reading.
        private func describe(_ thread: thread_act_t) -> ThreadCPU? {
            guard let basic = Self.basicInfo(of: thread), let identifier = Self.identifierInfo(of: thread) else { return nil }
            // The kernel's idle threads report no use of their own.
            let usage = basic.flags & TH_FLAGS_IDLE == 0 ? Double(basic.cpu_usage) / Double(TH_USAGE_SCALE) : 0
            return ThreadCPU(
                name: ThreadCPU.name(
                    pthreadName: Self.pthreadName(of: thread),
                    threadID: identifier.thread_id,
                    isMainThread: identifier.thread_id == mainThreadID
                ),
                threadID: identifier.thread_id,
                cpuUsage: usage
            )
        }
    }

    // thread_act_t is UInt32, so these read a thread through functions rather than an extension
    // on it, which every UInt32 in the file would carry.
    extension MachThreadSampler {
        /// The thread's scheduling state and recent CPU use, or `nil` if it has ended.
        fileprivate static func basicInfo(of thread: thread_act_t) -> thread_basic_info? {
            var info = thread_basic_info()
            var count = mach_msg_type_number_t(MemoryLayout<thread_basic_info_data_t>.size / MemoryLayout<natural_t>.size)
            let result = withUnsafeMutablePointer(to: &info) { pointer in
                pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                    thread_info(thread, thread_flavor_t(THREAD_BASIC_INFO), $0, &count)
                }
            }
            return result == KERN_SUCCESS ? info : nil
        }

        /// The thread's system-wide ID, or `nil` if it has ended.
        fileprivate static func identifierInfo(of thread: thread_act_t) -> thread_identifier_info? {
            var info = thread_identifier_info()
            var count = mach_msg_type_number_t(MemoryLayout<thread_identifier_info_data_t>.size / MemoryLayout<natural_t>.size)
            let result = withUnsafeMutablePointer(to: &info) { pointer in
                pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                    thread_info(thread, thread_flavor_t(THREAD_IDENTIFIER_INFO), $0, &count)
                }
            }
            return result == KERN_SUCCESS ? info : nil
        }

        /// The name the thread gave its pthread, empty when it set none, or `nil` when it has no
        /// pthread (or has ended).
        fileprivate static func pthreadName(of thread: thread_act_t) -> String? {
            // Both calls look the pthread up in libpthread's list of live threads under its lock,
            // so a thread that ends meanwhile gives nil or ESRCH rather than a dangling read.
            guard let pthread = pthread_from_mach_thread_np(thread) else { return nil }
            // MAXTHREADNAMESIZE, the longest name a pthread keeps.
            var buffer = [CChar](repeating: 0, count: 64)
            guard pthread_getname_np(pthread, &buffer, buffer.count) == 0 else { return nil }
            return String(bytes: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, encoding: .utf8)
        }
    }
#endif
