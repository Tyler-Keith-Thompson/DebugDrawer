// Installing puts an observer on the main run loop and starts a watcher thread in the process
// that runs it, so these run in a child process each, in a file of their own, as exit tests need
// one. The README's example is here, verbatim, rather than in DebugDrawerTests, which links core
// alone.
#if os(macOS) && DEBUG
    import DebugDrawer
    import DebugDrawerHangDetectorPlugin
    import Foundation
    import Testing

    @Suite("Hang Detector install, in a child process")
    struct HangDetectorInstallExitTests {
        @Test("Install registers Hangs and starts one watcher thread; installing again changes the threshold and starts no other")
        func install() async {
            await #expect(processExitsWith: .success) {
                func watcherCount() -> Int {
                    var threads: thread_act_array_t?
                    var count: mach_msg_type_number_t = 0
                    guard task_threads(mach_task_self_, &threads, &count) == KERN_SUCCESS, let threads else { return -1 }
                    defer {
                        vm_deallocate(mach_task_self_, vm_address_t(bitPattern: threads), vm_size_t(Int(count) * MemoryLayout<thread_t>.stride))
                    }
                    return (0 ..< Int(count)).count { index in
                        guard let thread = pthread_from_mach_thread_np(threads[index]) else { return false }
                        var name = [CChar](repeating: 0, count: 64)
                        pthread_getname_np(thread, &name, name.count)
                        return String(validating: name.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self) == "DebugDrawer hang watcher"
                    }
                }
                let before = watcherCount()
                let isRegistered = await MainActor.run {
                    HangDetector.install()
                    return DebugDrawer.shared.globalPlugins.contains { $0.title == "Hangs" }
                }
                let first = watcherCount()
                await MainActor.run { HangDetector.install(threshold: .milliseconds(500)) }
                let second = watcherCount()
                exit(before == 0 && isRegistered && first == 1 && second == 1 ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }

        @Test("A threshold of zero traps")
        func zeroThreshold() async {
            await #expect(processExitsWith: .failure) {
                await MainActor.run { HangDetector.install(threshold: .zero) }
            }
        }

        @Test("A negative threshold traps")
        func negativeThreshold() async {
            await #expect(processExitsWith: .failure) {
                await MainActor.run { HangDetector.install(threshold: .milliseconds(-1)) }
            }
        }

        @Test("README: Hang Detector")
        func readme() async {
            await #expect(processExitsWith: .success) {
                let isInstalled = await MainActor.run {
                    // At startup; a stall of the main thread over 250 ms is a hang.
                    HangDetector.install()

                    // Or with a threshold of the app's own, which the drawer can change later.
                    HangDetector.install(threshold: .milliseconds(100))

                    return DebugDrawer.shared.globalPlugins.contains { $0.title == "Hangs" }
                }
                exit(isInstalled ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }
    }
#endif
