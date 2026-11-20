// What runs, and when, through a real receiver: the watcher thread is counted among the process's
// threads by name, and the observers are looked for on the main run loop, so these run in a child
// process each (other tests in this process start monitors of their own), in a file of their own,
// as exit tests need one. Commands are written into the store as a sidecar would leave them, and
// the receiver performs them as it starts and at each `reevaluateGates()`.
#if os(macOS) && DEBUG
    import CoreFoundation
    @testable import DebugDrawerHangDetector
    @testable import DebugDrawerReceiver
    import Foundation
    import Testing

    /// The host's gate for the capability, which the test turns off.
    @MainActor
    private final class Gate {
        var isOpen = true
    }

    @Suite("Performance traces, in a child process", .timeLimit(.minutes(1)))
    struct PerformanceTracesExitTests {
        @Test("With the capability off, a sidecar's start in its session is refused and starts no watcher thread")
        func offStartsNothing() async {
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
                        return String(validating: name.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self) == HangMonitor.watcherName
                    }
                }
                @MainActor func isExpected() throws -> Bool {
                    let directory = FileManager.default.temporaryDirectory.appending(path: "PerformanceTracesExitTests-\(UUID().uuidString)")
                    let layout = AppGroupStoreLayout(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
                    guard layout.create() else { return false }
                    let commands: [(String, Data)] = try [
                        (DebugDrawerSessions.pluginID, TransportMessage.payload(DebugDrawerSessionCommand.open(duration: 60))),
                        (PerformanceTraces.pluginID, TransportMessage.payload(PerformanceTraces.Command.start))
                    ]
                    for (index, (id, payload)) in commands.enumerated() {
                        let document = StoreDocument(TransportMessage(kind: .command, pluginID: id, payload: payload))
                        try layout.write(document.encoded(), to: layout.commands.appending(path: "\(index).json"))
                    }
                    let sessions = DebugDrawerSessions(maximumDuration: 300)
                    let traces = PerformanceTraces(sessions: sessions)
                    let receiver = DebugDrawerReceiver(directory: directory, sessions: sessions)
                    // Another capability, as a receiver with none enabled opens no session.
                    receiver.enable(.diagnosticsCapture(DebugDrawerDiagnosticsCapture(sessions: sessions)))

                    try receiver.start()
                    defer { receiver.stop() }

                    let refused = sessions.auditLog.contains {
                        $0.capability == PerformanceTraces.pluginID && $0.event == .commandRefused(.unknownCapability)
                    }
                    return sessions.snapshot.isActive && refused && traces.monitor == nil && watcherCount() == 0
                        && traces.beginInterval("Off").recording == nil
                }
                exit(await MainActor.run { (try? isExpected()) == true } ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }

        @Test("Enabled: nothing runs outside a session; a start in one runs a watcher and the observers; the session's end removes both")
        func sessionStartsAndEnds() async {
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
                        return String(validating: name.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self) == HangMonitor.watcherName
                    }
                }
                @MainActor func isExpected() throws -> Bool {
                    let directory = FileManager.default.temporaryDirectory.appending(path: "PerformanceTracesExitTests-\(UUID().uuidString)")
                    let layout = AppGroupStoreLayout(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
                    guard layout.create(), let mainRunLoop = CFRunLoopGetMain() else { return false }
                    func send(_ id: String, _ payload: Data) throws {
                        let document = StoreDocument(TransportMessage(kind: .command, pluginID: id, payload: payload))
                        try layout.write(document.encoded(), to: layout.commands.appending(path: "\(UUID().uuidString).json"))
                    }
                    let sessions = DebugDrawerSessions(maximumDuration: 300)
                    let traces = PerformanceTraces(sessions: sessions)
                    let receiver = DebugDrawerReceiver(directory: directory, sessions: sessions)
                    receiver.enable(.performanceTraces(traces))
                    try send(PerformanceTraces.pluginID, TransportMessage.payload(PerformanceTraces.Command.start))

                    try receiver.start()
                    defer { receiver.stop() }
                    let outsideSession = watcherCount() == 0 && traces.monitor == nil && traces.beginInterval("Outside").recording == nil
                    try send(DebugDrawerSessions.pluginID, TransportMessage.payload(DebugDrawerSessionCommand.open(duration: 60)))
                    receiver.reevaluateGates()
                    let sessionWithoutStart = sessions.snapshot.isActive && watcherCount() == 0 && traces.monitor == nil
                    try send(PerformanceTraces.pluginID, TransportMessage.payload(PerformanceTraces.Command.start))
                    receiver.reevaluateGates()
                    guard let observers = traces.monitor?.observers else { return false }
                    let recording = watcherCount() == 1 && observers.allSatisfy { CFRunLoopContainsObserver(mainRunLoop, $0, .commonModes) }
                        && traces.beginInterval("Inside").recording != nil
                    try send(DebugDrawerSessions.pluginID, TransportMessage.payload(DebugDrawerSessionCommand.end))
                    receiver.reevaluateGates()

                    let ended = !sessions.snapshot.isActive && watcherCount() == 0 && traces.monitor == nil
                        && !observers.contains { CFRunLoopContainsObserver(mainRunLoop, $0, .commonModes) || CFRunLoopObserverIsValid($0) }
                    let reverted = sessions.auditLog.contains { $0.capability == PerformanceTraces.pluginID && $0.event == .changeReverted }
                    return outsideSession && sessionWithoutStart && recording && ended && reverted
                }
                exit(await MainActor.run { (try? isExpected()) == true } ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }

        @Test("The session's expiry ends the watcher thread and removes the observers")
        func expiryEnds() async {
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
                        return String(validating: name.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self) == HangMonitor.watcherName
                    }
                }
                @MainActor func isExpected() throws -> Bool {
                    let directory = FileManager.default.temporaryDirectory.appending(path: "PerformanceTracesExitTests-\(UUID().uuidString)")
                    let layout = AppGroupStoreLayout(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
                    guard layout.create() else { return false }
                    let commands: [(String, Data)] = try [
                        (DebugDrawerSessions.pluginID, TransportMessage.payload(DebugDrawerSessionCommand.open(duration: 60))),
                        (PerformanceTraces.pluginID, TransportMessage.payload(PerformanceTraces.Command.start))
                    ]
                    for (index, (id, payload)) in commands.enumerated() {
                        let document = StoreDocument(TransportMessage(kind: .command, pluginID: id, payload: payload))
                        try layout.write(document.encoded(), to: layout.commands.appending(path: "\(index).json"))
                    }
                    let clock = MovableClock(Date())
                    let timer = ManualTimer()
                    let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: clock, timer: timer)
                    let traces = PerformanceTraces(sessions: sessions)
                    let receiver = DebugDrawerReceiver(directory: directory, sessions: sessions)
                    receiver.enable(.performanceTraces(traces))
                    try receiver.start()
                    defer { receiver.stop() }
                    guard let observers = traces.monitor?.observers else { return false }
                    let recording = watcherCount() == 1

                    clock.set(clock.now.addingTimeInterval(61))
                    timer.fireNow()

                    return recording && !sessions.snapshot.isActive && watcherCount() == 0 && traces.monitor == nil
                        && !observers.contains { CFRunLoopObserverIsValid($0) }
                }
                exit(await MainActor.run { (try? isExpected()) == true } ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }

        @Test("The receiver's gate turning off ends the session, the watcher thread and the observers")
        func receiverGateEnds() async {
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
                        return String(validating: name.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self) == HangMonitor.watcherName
                    }
                }
                @MainActor func isExpected() throws -> Bool {
                    let directory = FileManager.default.temporaryDirectory.appending(path: "PerformanceTracesExitTests-\(UUID().uuidString)")
                    let layout = AppGroupStoreLayout(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
                    guard layout.create() else { return false }
                    let commands: [(String, Data)] = try [
                        (DebugDrawerSessions.pluginID, TransportMessage.payload(DebugDrawerSessionCommand.open(duration: 60))),
                        (PerformanceTraces.pluginID, TransportMessage.payload(PerformanceTraces.Command.start))
                    ]
                    for (index, (id, payload)) in commands.enumerated() {
                        let document = StoreDocument(TransportMessage(kind: .command, pluginID: id, payload: payload))
                        try layout.write(document.encoded(), to: layout.commands.appending(path: "\(index).json"))
                    }
                    let sessions = DebugDrawerSessions(maximumDuration: 300)
                    let traces = PerformanceTraces(sessions: sessions)
                    let receiver = DebugDrawerReceiver(directory: directory, sessions: sessions)
                    receiver.enable(.performanceTraces(traces))
                    try receiver.start()
                    defer { receiver.stop() }
                    guard let observers = traces.monitor?.observers else { return false }
                    let recording = watcherCount() == 1

                    receiver.isAllowed = { false }

                    return recording && !sessions.snapshot.isActive && watcherCount() == 0 && traces.monitor == nil
                        && !observers.contains { CFRunLoopObserverIsValid($0) }
                }
                exit(await MainActor.run { (try? isExpected()) == true } ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }

        @Test("The capability's gate turning off ends the watcher thread and the observers while the session goes on")
        func capabilityGateEnds() async {
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
                        return String(validating: name.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self) == HangMonitor.watcherName
                    }
                }
                @MainActor func isExpected() throws -> Bool {
                    let directory = FileManager.default.temporaryDirectory.appending(path: "PerformanceTracesExitTests-\(UUID().uuidString)")
                    let layout = AppGroupStoreLayout(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
                    guard layout.create() else { return false }
                    let commands: [(String, Data)] = try [
                        (DebugDrawerSessions.pluginID, TransportMessage.payload(DebugDrawerSessionCommand.open(duration: 60))),
                        (PerformanceTraces.pluginID, TransportMessage.payload(PerformanceTraces.Command.start))
                    ]
                    for (index, (id, payload)) in commands.enumerated() {
                        let document = StoreDocument(TransportMessage(kind: .command, pluginID: id, payload: payload))
                        try layout.write(document.encoded(), to: layout.commands.appending(path: "\(index).json"))
                    }
                    let sessions = DebugDrawerSessions(maximumDuration: 300)
                    let traces = PerformanceTraces(sessions: sessions)
                    let receiver = DebugDrawerReceiver(directory: directory, sessions: sessions)
                    let gate = Gate()
                    receiver.enable(.performanceTraces(traces), isAllowed: { gate.isOpen })
                    try receiver.start()
                    defer { receiver.stop() }
                    guard let observers = traces.monitor?.observers else { return false }
                    let recording = watcherCount() == 1

                    gate.isOpen = false
                    receiver.reevaluateGates()

                    return recording && sessions.snapshot.isActive && watcherCount() == 0 && traces.monitor == nil
                        && !observers.contains { CFRunLoopObserverIsValid($0) }
                }
                exit(await MainActor.run { (try? isExpected()) == true } ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }

        @Test("A hang of the main thread itself, with the shipped watcher, is recorded with the main thread's stack")
        func mainThreadHang() async {
            await #expect(processExitsWith: .success) {
                // The main run loop, turned here as an app's is: it waits once, then a timer keeps the
                // main thread busy past the hang threshold and stops the loop.
                @MainActor func turnMainRunLoopThroughAHang() {
                    let timer = CFRunLoopTimerCreateWithHandler(nil, CFAbsoluteTimeGetCurrent() + 0.05, 0, 0, 0) { _ in
                        let end = ContinuousClock.now + .milliseconds(400)
                        while ContinuousClock.now < end {}
                        CFRunLoopStop(CFRunLoopGetMain())
                    }
                    CFRunLoopAddTimer(CFRunLoopGetMain(), timer, .defaultMode)
                    CFRunLoopRunInMode(.defaultMode, 10, false)
                }
                @MainActor func hangIsRecorded() async throws -> Bool {
                    let directory = FileManager.default.temporaryDirectory.appending(path: "PerformanceTracesExitTests-\(UUID().uuidString)")
                    let layout = AppGroupStoreLayout(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
                    guard layout.create() else { throw CocoaError(.fileWriteUnknown) }
                    let commands: [(String, Data)] = try [
                        (DebugDrawerSessions.pluginID, TransportMessage.payload(DebugDrawerSessionCommand.open(duration: 60))),
                        (PerformanceTraces.pluginID, TransportMessage.payload(PerformanceTraces.Command.start))
                    ]
                    for (index, (id, payload)) in commands.enumerated() {
                        let document = StoreDocument(TransportMessage(kind: .command, pluginID: id, payload: payload))
                        try layout.write(document.encoded(), to: layout.commands.appending(path: "\(index).json"))
                    }
                    let sessions = DebugDrawerSessions(maximumDuration: 300)
                    let traces = PerformanceTraces(sessions: sessions)
                    let receiver = DebugDrawerReceiver(directory: directory, sessions: sessions)
                    receiver.enable(.performanceTraces(traces))
                    try receiver.start()
                    turnMainRunLoopThroughAHang()
                    // The stall is named on the main actor once the loop turns again: wait for it.
                    for await snapshot in traces.$snapshot.values where !snapshot.stalls.isEmpty {
                        let stall = snapshot.stalls[0]
                        let lines = stall.frames.enumerated().map { $1.line(index: $0) }
                        // The test runs in a bundle `xctest` loads, so its frames aren't the executable's:
                        // every frame in an image carries the image's UUID and its offset into it.
                        let imaged = stall.frames.filter { $0.image != nil }
                        let isExpected = stall.kind == .hang && stall.duration >= .milliseconds(250)
                            && lines.contains { $0.contains("CFRunLoop") } && !imaged.isEmpty
                            && imaged.allSatisfy { $0.imageUUID != nil && $0.imageOffset != nil }
                        return isExpected
                    }
                    return false
                }
                let isRecorded = (try? await hangIsRecorded()) ?? false
                exit(isRecorded ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }

        @Test("Hitch and hang thresholds that aren't positive, or a hitch threshold past the hang threshold, trap")
        func thresholdsTrap() async {
            await #expect(processExitsWith: .failure) {
                await MainActor.run {
                    _ = PerformanceTraces(sessions: DebugDrawerSessions(maximumDuration: 60), hitchThreshold: .zero)
                }
            }
            await #expect(processExitsWith: .failure) {
                await MainActor.run {
                    _ = PerformanceTraces(
                        sessions: DebugDrawerSessions(maximumDuration: 60), hitchThreshold: .milliseconds(300), hangThreshold: .milliseconds(250)
                    )
                }
            }
        }

        @Test("Limits that keep no stall or no interval trap")
        func emptyLimitsTrap() async {
            await #expect(processExitsWith: .failure) {
                _ = PerformanceTraces.Limits(stalls: 0, intervals: 1)
            }
            await #expect(processExitsWith: .failure) {
                _ = PerformanceTraces.Limits(stalls: 1, intervals: 0)
            }
        }
    }
#endif
