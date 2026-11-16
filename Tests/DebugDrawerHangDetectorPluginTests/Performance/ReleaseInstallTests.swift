// The release stand-in. `--config=release` builds and runs only the performance targets, so this
// is where a test is compiled without DEBUG, as an app's release build is; in debug the file is
// empty, and HangDetectorInstallExitTests checks the opposite.
#if !DEBUG
    import DebugDrawerHangDetectorPlugin
    import Darwin
    import Testing

    @Suite
    struct ReleaseInstallTests {
        @MainActor
        @Test("In release, install compiles and starts no watcher thread")
        func installStartsNothing() {
            func threadNames() -> [String] {
                var threads: thread_act_array_t?
                var count: mach_msg_type_number_t = 0
                guard task_threads(mach_task_self_, &threads, &count) == KERN_SUCCESS, let threads else { return [] }
                defer {
                    vm_deallocate(mach_task_self_, vm_address_t(bitPattern: threads), vm_size_t(Int(count) * MemoryLayout<thread_t>.stride))
                }
                return (0 ..< Int(count)).compactMap { index in
                    guard let thread = pthread_from_mach_thread_np(threads[index]) else { return nil }
                    var name = [CChar](repeating: 0, count: 64)
                    pthread_getname_np(thread, &name, name.count)
                    return String(validating: name.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
                }
            }
            let before = threadNames().count

            HangDetector.install(threshold: .milliseconds(1))
            let actual = threadNames()

            #expect(!actual.contains("DebugDrawer hang watcher"))
            #expect(actual.count == before)
        }
    }
#endif
