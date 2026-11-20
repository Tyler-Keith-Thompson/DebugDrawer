// Uninstalling removes an observer from the main run loop and ends a watcher thread of the process
// that runs it, so these run in a child process each, in a file of their own, as exit tests need
// one.
#if os(macOS) && DEBUG
    import CoreFoundation
    @testable import DebugDrawer
    import DebugDrawerHangDetector
    @testable import DebugDrawerHangDetectorPlugin
    import Foundation
    import Testing

    @Suite("Hang Detector uninstall, in a child process", .timeLimit(.minutes(1)))
    struct HangDetectorUninstallExitTests {
        @Test("Unregistering ends the watcher thread; unregistering again changes nothing; installing again starts one")
        func endsWatcher() async {
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
                await MainActor.run { HangDetector.install() }
                let installed = watcherCount()

                let isListed = await MainActor.run {
                    DebugDrawer.shared.unregisterGlobal(id: HangDetectorPlugin.pluginID)
                    return DebugDrawer.shared.globalPlugins.contains { $0.id == HangDetectorPlugin.pluginID }
                }
                let uninstalled = watcherCount()
                await MainActor.run { DebugDrawer.shared.unregisterGlobal(id: HangDetectorPlugin.pluginID) }
                let twice = watcherCount()
                await MainActor.run { HangDetector.install() }
                let reinstalled = watcherCount()

                exit(installed == 1 && !isListed && uninstalled == 0 && twice == 0 && reinstalled == 1 ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }

        @Test("A plugin in two drawers watches until the last removes it, which forgets its hangs")
        func twoDrawers() async {
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
                @MainActor func isExpected() -> Bool {
                    let suite = "HangDetectorUninstallExitTests.\(UUID().uuidString)"
                    guard let first = UserDefaults(suiteName: suite + ".first"), let second = UserDefaults(suiteName: suite + ".second") else {
                        return false
                    }
                    let firstDrawer = DebugDrawer(defaults: first)
                    let secondDrawer = DebugDrawer(defaults: second)
                    let store = HangStore(threshold: .milliseconds(250))
                    store.add(HangEvent(
                        id: UUID(), date: Date(timeIntervalSince1970: 1), duration: .milliseconds(300), frames: [], source: .detected, isSeen: false
                    ))
                    let sut = HangDetectorPlugin(store: store)

                    firstDrawer.registerGlobal(sut)
                    secondDrawer.registerGlobal(sut)
                    let watchersInBoth = watcherCount()
                    firstDrawer.unregisterGlobal(id: sut.id)
                    let watchersInSecond = watcherCount()
                    let eventsInSecond = store.events.count
                    secondDrawer.unregisterGlobal(id: sut.id)

                    return watchersInBoth == 1 && watchersInSecond == 1 && eventsInSecond == 1
                        && watcherCount() == 0 && store.events.isEmpty
                        && !secondDrawer.globalPlugins.contains { $0.id == sut.id }
                }
                exit(await MainActor.run { isExpected() } ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }

        @Test("Stopping a monitor removes both its observers from the run loop and ends its watcher thread, at once")
        func stopRemovesObservers() async {
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
                @MainActor func isStopped() -> Bool {
                    guard let runLoop = CFRunLoopGetMain() else { return false }
                    let sut = HangMonitor(
                        runLoop: runLoop, sampler: MachThreadStackSampler.currentThread(), threshold: .milliseconds(250)
                    ) { _ in }
                    let observedWhileRunning = sut.observers.allSatisfy { CFRunLoopContainsObserver(runLoop, $0, .commonModes) }
                    let watchersWhileRunning = watcherCount()

                    sut.stop()
                    sut.stop()

                    return observedWhileRunning && watchersWhileRunning == 1
                        && !sut.observers.contains { CFRunLoopContainsObserver(runLoop, $0, .commonModes) || CFRunLoopObserverIsValid($0) }
                        && watcherCount() == 0
                }
                exit(await MainActor.run { isStopped() } ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }
    }
#endif
