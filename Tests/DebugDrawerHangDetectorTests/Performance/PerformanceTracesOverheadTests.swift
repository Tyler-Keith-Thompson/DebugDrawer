// What recording performance traces costs the app while a sidecar's session records, measured in
// the build an app ships: `just test-release` (`--config=release`) builds and runs this target
// optimized, without DEBUG, and so does `just test` in debug. Each test prints what it measured;
// `PerformanceTraces`' documentation and the README quote the release figures. The bounds are
// several times those figures, so a change that makes the observer or a signpost do real work
// (allocate, log, symbolicate) fails.
//
// Each test counts CPU time rather than the time on a clock on the wall, so other processes loading
// the machine don't show up as cost: the test thread's (CLOCK_THREAD_CPUTIME_ID), which stops while
// the thread is descheduled, where the work measured runs on it, and for the run loop turns the
// CPU time of the run loop's thread and of the watcher thread, which is where a watched turn's work
// runs. It keeps the fastest of several batches, which leaves out a batch slowed by a context
// switch's cold caches or a stretch on an efficiency core.
import CoreFoundation
import DebugDrawerHangDetector
import DebugDrawerReceiver
import Foundation
import Testing

@Suite(.serialized, .timeLimit(.minutes(1)))
struct PerformanceTracesOverheadTests {
    @Test("A checkpoint with no stall costs under 2 µs")
    func checkpointCost() {
        let sut = HangMonitorState(threshold: PerformanceTraces.defaultHitchThreshold)
        let batches = 10
        let iterations = 50000
        var fastest = Duration.seconds(1)

        for _ in 0 ..< batches {
            let start = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
            for _ in 0 ..< iterations {
                _ = sut.checkpoint(isAboutToWait: false)
                _ = sut.checkpoint(isAboutToWait: true)
            }
            let end = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
            fastest = min(fastest, .nanoseconds(end - start) / (iterations * 2))
        }

        print("Performance traces: a checkpoint costs \(fastest) of CPU time")
        #expect(fastest < .microseconds(2))
    }

    @Test("A watcher wake with the thread idle costs under 5 µs")
    func tickCost() {
        let sut = HangMonitorState(threshold: PerformanceTraces.defaultHitchThreshold)
        _ = sut.checkpoint(isAboutToWait: true)
        let sampler = MachThreadStackSampler.currentThread()
        let batches = 10
        let iterations = 20000
        var fastest = Duration.seconds(1)

        for _ in 0 ..< batches {
            let start = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
            for _ in 0 ..< iterations {
                sut.tick(sampler)
            }
            let end = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
            fastest = min(fastest, .nanoseconds(end - start) / iterations)
        }

        print("Performance traces: a watcher wake costs \(fastest) of CPU time, \(HangTracker.ticksPerThreshold * 10) wakes a second by default")
        #expect(fastest < .microseconds(5))
    }

    @Test("The observers add under 10 µs to a turn of a run loop that waits and is woken")
    func runLoopTurnCost() throws {
        let batches = 10
        let turns = 10000

        let without = try Self.fastestTurn(batches: batches, turns: turns, watched: false)
        let with = try Self.fastestTurn(batches: batches, turns: turns, watched: true)
        let actual = with - without

        print("Performance traces: a run loop turn takes \(without) of CPU time unwatched, \(with) watched, \(actual) more")
        #expect(actual < .microseconds(10))
    }

    @Test("Sampling a stopped thread's stack costs under 1 ms")
    func sampleCost() throws {
        let ready = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let done = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var sampler: MachThreadStackSampler?
        let thread = Thread {
            sampler = .currentThread()
            ready.signal()
            _ = release.wait(timeout: .now() + 30)
            done.signal()
        }
        thread.start()
        ready.wait()
        let sut = try #require(sampler)
        let frames = UnsafeMutableBufferPointer<UInt>.allocate(capacity: HangMonitorState.maximumFrames)
        defer { frames.deallocate() }
        let batches = 10
        let iterations = 100
        var fastest = Duration.seconds(1)

        // The sampled thread is stopped while the test thread reads its stack, so the test
        // thread's CPU time covers the work of the stop.
        for _ in 0 ..< batches {
            let start = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
            for _ in 0 ..< iterations {
                _ = sut.sample(into: frames)
            }
            let end = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
            fastest = min(fastest, .nanoseconds(end - start) / iterations)
        }
        release.signal()
        done.wait()

        print("Performance traces: sampling a thread's stack stops it for \(fastest) of CPU time")
        #expect(fastest < .milliseconds(1))
    }

    @Test("Naming a stack's frames costs under 50 µs a frame")
    func symbolicationCost() {
        let addresses = Thread.callStackReturnAddresses.map { UInt(truncating: $0) }
        let batches = 10
        let iterations = 20
        var fastest = Duration.seconds(1)

        for _ in 0 ..< batches {
            let start = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
            for _ in 0 ..< iterations {
                _ = Symbolicator.frames(for: addresses)
            }
            let end = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
            fastest = min(fastest, .nanoseconds(end - start) / (iterations * max(addresses.count, 1)))
        }

        print("Performance traces: naming a frame costs \(fastest) of CPU time, \(addresses.count) frames")
        #expect(fastest < .microseconds(50))
    }

    @MainActor
    @Test("A signpost interval costs under 5 µs while recording and under 1 µs while nothing records")
    func signpostCost() {
        let sessions = DebugDrawerSessions(maximumDuration: 300)
        let sut = PerformanceTraces(sessions: sessions, limits: PerformanceTraces.Limits(stalls: 1, intervals: 100))
        let batches = 10
        let iterations = 20000
        var idle = Duration.seconds(1)
        var recording = Duration.seconds(1)

        for _ in 0 ..< batches {
            let start = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
            for _ in 0 ..< iterations {
                sut.endInterval(sut.beginInterval("Overhead"))
            }
            let end = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
            idle = min(idle, .nanoseconds(end - start) / iterations)
        }
        sessions.perform(.open(duration: 60))
        sut.perform(.start)
        for _ in 0 ..< batches {
            let start = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
            for _ in 0 ..< iterations {
                sut.endInterval(sut.beginInterval("Overhead"))
            }
            let end = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
            recording = min(recording, .nanoseconds(end - start) / iterations)
        }
        sut.perform(.stop)
        sessions.end()

        print("Performance traces: a signpost interval costs \(idle) of CPU time while nothing records, \(recording) while recording")
        #expect(idle < .microseconds(1))
        #expect(recording < .microseconds(5))
    }

    /// The least CPU time a turn of a fresh thread's run loop takes, over `batches` batches of
    /// `turns` turns, each a block that schedules the next and wakes the loop, so every turn waits
    /// and wakes as an app's does. It counts the run loop thread's CPU time and, when `watched`,
    /// the hang watcher thread's too.
    private static func fastestTurn(batches: Int, turns: Int, watched: Bool) throws -> Duration {
        let ready = DispatchSemaphore(value: 0)
        let start = DispatchSemaphore(value: 0)
        let done = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var runLoop: CFRunLoop?
        nonisolated(unsafe) var sampler: MachThreadStackSampler?
        nonisolated(unsafe) var watcherRead = true
        nonisolated(unsafe) var fastest = Duration.seconds(1)
        let thread = Thread {
            let current = CFRunLoopGetCurrent()
            runLoop = current
            sampler = .currentThread()
            // Keeps the run loop running between blocks, which aren't sources.
            let keepAlive = CFRunLoopTimerCreateWithHandler(nil, .greatestFiniteMagnitude, 0, 0, 0) { _ in }
            CFRunLoopAddTimer(current, keepAlive, .defaultMode)
            nonisolated(unsafe) var remaining = 0
            nonisolated(unsafe) var turn: (() -> Void)?
            turn = {
                remaining -= 1
                if remaining == 0 {
                    CFRunLoopStop(current)
                } else {
                    CFRunLoopPerformBlock(current, CFRunLoopMode.defaultMode.rawValue, turn)
                    CFRunLoopWakeUp(current)
                }
            }
            ready.signal()
            start.wait()
            // Looked up once the monitor has started it.
            let watcher = watched ? Self.watcherThread() : nil
            let watcherTime = { watched ? watcher.flatMap(Self.cpuTime(of:)) : 0 }
            for _ in 0 ..< batches {
                remaining = turns
                CFRunLoopPerformBlock(current, CFRunLoopMode.defaultMode.rawValue, turn)
                let watcherStart = watcherTime()
                let threadStart = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
                CFRunLoopRun()
                let threadEnd = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
                let watcherEnd = watcherTime()
                guard let watcherStart, let watcherEnd else {
                    watcherRead = false
                    continue
                }
                fastest = min(fastest, .nanoseconds((threadEnd - threadStart) + (watcherEnd - watcherStart)) / turns)
            }
            turn = nil
            if let watcher {
                mach_port_deallocate(mach_task_self_, watcher)
            }
            done.signal()
        }
        thread.start()
        ready.wait()
        let monitor = watched
            ? HangMonitor(
                runLoop: try #require(runLoop), sampler: try #require(sampler), threshold: PerformanceTraces.defaultHitchThreshold
            ) { _ in }
            : nil
        start.signal()
        done.wait()
        withExtendedLifetime(monitor) {}
        try #require(watcherRead, "Exactly one hang watcher thread runs, and its CPU time can be read")
        return fastest
    }

    /// The hang watcher thread's port, if exactly one runs; the caller deallocates it.
    private static func watcherThread() -> thread_act_t? {
        var threads: thread_act_array_t?
        var count: mach_msg_type_number_t = 0
        guard task_threads(mach_task_self_, &threads, &count) == KERN_SUCCESS, let threads else { return nil }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: threads), vm_size_t(Int(count) * MemoryLayout<thread_t>.stride))
        }
        let ports = (0 ..< Int(count)).map { threads[$0] }
        let watchers = ports.filter { port in
            guard let thread = pthread_from_mach_thread_np(port) else { return false }
            var name = [CChar](repeating: 0, count: 64)
            pthread_getname_np(thread, &name, name.count)
            return String(bytes: name.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, encoding: .utf8) == HangMonitor.watcherName
        }
        let watcher = watchers.count == 1 ? watchers[0] : nil
        for port in ports where port != watcher {
            mach_port_deallocate(mach_task_self_, port)
        }
        return watcher
    }

    /// The CPU time, user and system, in nanoseconds, that `thread` has run for, to the
    /// microsecond; `nil` if it can't be read.
    private static func cpuTime(of thread: thread_act_t) -> UInt64? {
        var info = thread_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<thread_basic_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { fields in
                thread_info(thread, thread_flavor_t(THREAD_BASIC_INFO), fields, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let microseconds = (Int64(info.user_time.seconds) + Int64(info.system_time.seconds)) * 1_000_000
            + Int64(info.user_time.microseconds) + Int64(info.system_time.microseconds)
        return UInt64(microseconds) * 1000
    }
}
