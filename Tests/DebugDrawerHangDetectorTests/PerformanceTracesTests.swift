// The recorder driven directly, as the receiver would within a session: what start, stop and export
// do, what a stall becomes (its kind, duration and stack), which signpost intervals are kept, the
// bounds, and that the monitor runs only while a sidecar records. The watched thread is a helper
// thread's run loop (StallingThread), since a test runner's main thread doesn't turn its run loop;
// a stall is named on the main actor after it ends, so each test reads the snapshots the model
// publishes until the one it waits for.
#if DEBUG
    import Combine
    import CoreFoundation
    @testable import DebugDrawerHangDetector
    @testable import DebugDrawerReceiver
    import Foundation
    import Testing

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct PerformanceTracesTests {
        @Test("A stall while recording is kept with its duration and the stack it was stuck on, each frame with its image's UUID and offset")
        func recordsStall() async throws {
            let clock = MovableClock(Date())
            let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 10, clock: clock, timer: ManualTimer())
            let thread = StallingThread()
            let sut = try PerformanceTraces(
                sessions: sessions, hitchThreshold: .milliseconds(50), hangThreshold: .milliseconds(50), limits: .standard,
                now: { clock.now }, watchedThread: { (thread.runLoop, thread.sampler) }
            )
            let (published, publish) = AsyncStream<PerformanceTraces.Snapshot>.makeStream()
            let subscription = sut.$snapshot.sink { publish.yield($0) }
            defer { subscription.cancel() }
            var changes = published.makeAsyncIterator()
            sessions.perform(.open(duration: 60))

            sut.perform(.start)
            thread.stall()
            var actual = sut.snapshot
            while actual.stalls.isEmpty, let next = await changes.next() {
                actual = next
            }

            let stall = try #require(actual.stalls.first)
            let lines = stall.frames.enumerated().map { $1.line(index: $0) }
            let named = stall.frames.filter { $0.image != nil }
            #expect(thread.finished())
            #expect(actual.sessionID == sessions.snapshot.session?.id)
            #expect(actual.stalls.count == 1)
            #expect(stall.id == 1)
            #expect(stall.kind == .hang)
            #expect(stall.duration >= .milliseconds(50))
            #expect(lines.prefix(4).contains { $0.contains("semaphore") || $0.contains("ulock") })
            #expect(lines.contains { $0.contains("CFRunLoop") })
            #expect(!named.isEmpty)
            #expect(named.allSatisfy { $0.imageUUID != nil && $0.imageOffset != nil })
            #expect(named.allSatisfy { frame in
                var info = Dl_info()
                guard let pointer = UnsafeRawPointer(bitPattern: UInt(frame.address)), dladdr(pointer, &info) != 0 else { return false }
                return frame.imageLoadAddress == UInt64(UInt(bitPattern: info.dli_fbase))
            })
        }

        @Test("A stall shorter than the hang threshold is a hitch")
        func hitch() async throws {
            let clock = MovableClock(Date())
            let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 10, clock: clock, timer: ManualTimer())
            let thread = StallingThread()
            let sut = try PerformanceTraces(
                sessions: sessions, hitchThreshold: .milliseconds(50), hangThreshold: .seconds(20), limits: .standard,
                now: { clock.now }, watchedThread: { (thread.runLoop, thread.sampler) }
            )
            let (published, publish) = AsyncStream<PerformanceTraces.Snapshot>.makeStream()
            let subscription = sut.$snapshot.sink { publish.yield($0) }
            defer { subscription.cancel() }
            var changes = published.makeAsyncIterator()
            sessions.perform(.open(duration: 60))

            sut.perform(.start)
            thread.stall()
            var actual = sut.snapshot
            while actual.stalls.isEmpty, let next = await changes.next() {
                actual = next
            }

            #expect(thread.finished())
            #expect(actual.stalls.map(\.kind) == [.hitch])
        }

        @Test("Outside a session, start starts no monitor and records no interval")
        func noSession() throws {
            let clock = MovableClock(Date())
            let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 10, clock: clock, timer: ManualTimer())
            let sut = try PerformanceTraces(
                sessions: sessions, hitchThreshold: .milliseconds(100), hangThreshold: .milliseconds(250), limits: .standard,
                now: { clock.now }, watchedThread: { (CFRunLoopGetMain(), MachThreadStackSampler.currentThread()) }
            )

            sut.perform(.start)
            let interval = sut.beginInterval("Outside")
            sut.endInterval(interval)

            #expect(sut.monitor == nil)
            #expect(interval.recording == nil)
            #expect(!sut.snapshot.isRecording)
            #expect(sut.snapshot.intervals.isEmpty)
        }

        @Test("Before start, in an open session, nothing runs and an interval records nothing")
        func sessionWithoutStart() throws {
            let clock = MovableClock(Date())
            let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 10, clock: clock, timer: ManualTimer())
            let sut = try PerformanceTraces(
                sessions: sessions, hitchThreshold: .milliseconds(100), hangThreshold: .milliseconds(250), limits: .standard,
                now: { clock.now }, watchedThread: { (CFRunLoopGetMain(), MachThreadStackSampler.currentThread()) }
            )
            sessions.perform(.open(duration: 60))

            let interval = sut.beginInterval("Before start")

            #expect(sut.monitor == nil)
            #expect(interval.recording == nil)
            #expect(!sut.snapshot.isRecording)
        }

        @Test("Stop removes the monitor's observers from the run loop and invalidates them, and empties the recording")
        func stopTearsDown() throws {
            let clock = MovableClock(Date())
            let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 10, clock: clock, timer: ManualTimer())
            let runLoop = try #require(CFRunLoopGetMain())
            let sut = try PerformanceTraces(
                sessions: sessions, hitchThreshold: .milliseconds(100), hangThreshold: .milliseconds(250), limits: .standard,
                now: { clock.now }, watchedThread: { (runLoop, MachThreadStackSampler.currentThread()) }
            )
            sessions.perform(.open(duration: 60))
            sut.perform(.start)
            let observers = try #require(sut.monitor?.observers)
            let observedWhileRecording = observers.allSatisfy { CFRunLoopContainsObserver(runLoop, $0, .commonModes) }
            sut.endInterval(sut.beginInterval("Kept until stop"))

            sut.perform(.stop)

            let expected = PerformanceTraces.Snapshot(
                sessionID: nil, executable: Bundle.main.executableURL?.lastPathComponent,
                hitchThreshold: .milliseconds(100), hangThreshold: .milliseconds(250), stalls: [], intervals: [],
                droppedStalls: 0, droppedIntervals: 0, limits: .standard, exports: []
            )
            #expect(observedWhileRecording)
            #expect(sut.monitor == nil)
            #expect(!observers.contains { CFRunLoopContainsObserver(runLoop, $0, .commonModes) || CFRunLoopObserverIsValid($0) })
            #expect(sut.snapshot == expected)
            #expect(sut.beginInterval("After stop").recording == nil)
        }

        @Test("The session's end and its expiry each stop the monitor")
        func sessionEndAndExpiry() throws {
            let clock = MovableClock(Date())
            let timer = ManualTimer()
            let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 10, clock: clock, timer: timer)
            let runLoop = try #require(CFRunLoopGetMain())
            let sut = try PerformanceTraces(
                sessions: sessions, hitchThreshold: .milliseconds(100), hangThreshold: .milliseconds(250), limits: .standard,
                now: { clock.now }, watchedThread: { (runLoop, MachThreadStackSampler.currentThread()) }
            )
            sessions.perform(.open(duration: 60))
            sut.perform(.start)
            let firstObservers = try #require(sut.monitor?.observers)

            sessions.end()
            let afterEnd = sut.monitor
            sessions.perform(.open(duration: 60))
            sut.perform(.start)
            let secondObservers = try #require(sut.monitor?.observers)
            clock.set(clock.now.addingTimeInterval(61))
            timer.fireNow()

            #expect(afterEnd == nil)
            #expect(sut.monitor == nil)
            #expect(!sessions.snapshot.isActive)
            #expect(!(firstObservers + secondObservers).contains { CFRunLoopObserverIsValid($0) })
            #expect(!sut.snapshot.isRecording)
        }

        @Test("An interval begun and ended while recording is kept with its name, start and duration; one begun before or ended after isn't")
        func intervals() async throws {
            let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
            let clock = MovableClock(start)
            let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 10, clock: clock, timer: ManualTimer())
            let runLoop = try #require(CFRunLoopGetMain())
            let sut = try PerformanceTraces(
                sessions: sessions, hitchThreshold: .milliseconds(100), hangThreshold: .milliseconds(250), limits: .standard,
                now: { clock.now }, watchedThread: { (runLoop, MachThreadStackSampler.currentThread()) }
            )
            let (published, publish) = AsyncStream<PerformanceTraces.Snapshot>.makeStream()
            let subscription = sut.$snapshot.sink { publish.yield($0) }
            defer { subscription.cancel() }
            var changes = published.makeAsyncIterator()
            sessions.perform(.open(duration: 60))
            let beforeStart = sut.beginInterval("Before start")
            sut.perform(.start)

            let loadFeed = sut.beginInterval("Load feed")
            clock.set(start.addingTimeInterval(0.5))
            sut.endInterval(loadFeed)
            sut.endInterval(beforeStart)
            var actual = sut.snapshot
            while actual.intervals.isEmpty, let next = await changes.next() {
                actual = next
            }
            let endsAfterStop = sut.beginInterval("Ends after stop")
            sut.perform(.stop)
            sut.endInterval(endsAfterStop)

            let expected = [PerformanceTraces.SignpostInterval(id: 1, name: "Load feed", began: start, duration: .milliseconds(500))]
            #expect(actual.intervals == expected)
            #expect(sut.snapshot.intervals.isEmpty)
        }

        @Test("Past the interval limit the oldest go, each one dropped counted")
        func intervalLimit() async throws {
            let clock = MovableClock(Date(timeIntervalSinceReferenceDate: 800_000_000))
            let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 10, clock: clock, timer: ManualTimer())
            let runLoop = try #require(CFRunLoopGetMain())
            let sut = try PerformanceTraces(
                sessions: sessions, hitchThreshold: .milliseconds(100), hangThreshold: .milliseconds(250),
                limits: try PerformanceTraces.Limits(stalls: 1, intervals: 2),
                now: { clock.now }, watchedThread: { (runLoop, MachThreadStackSampler.currentThread()) }
            )
            let (published, publish) = AsyncStream<PerformanceTraces.Snapshot>.makeStream()
            let subscription = sut.$snapshot.sink { publish.yield($0) }
            defer { subscription.cancel() }
            var changes = published.makeAsyncIterator()
            sessions.perform(.open(duration: 60))
            sut.perform(.start)

            sut.endInterval(sut.beginInterval("One"))
            sut.endInterval(sut.beginInterval("Two"))
            sut.endInterval(sut.beginInterval("Three"))
            var actual = sut.snapshot
            while actual.intervals.last?.name != "Three", let next = await changes.next() {
                actual = next
            }

            #expect(actual.intervals.map(\.name) == ["Two", "Three"])
            #expect(actual.intervals.map(\.id) == [2, 3])
            #expect(actual.droppedIntervals == 1)
            sut.perform(.stop)
        }

        @Test("An interval ending at or after the session's expiry isn't kept, even before the expiry timer fires")
        func intervalAfterExpiry() throws {
            let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
            let clock = MovableClock(start)
            let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 10, clock: clock, timer: ManualTimer())
            let runLoop = try #require(CFRunLoopGetMain())
            let sut = try PerformanceTraces(
                sessions: sessions, hitchThreshold: .milliseconds(100), hangThreshold: .milliseconds(250), limits: .standard,
                now: { clock.now }, watchedThread: { (runLoop, MachThreadStackSampler.currentThread()) }
            )
            sessions.perform(.open(duration: 60))
            sut.perform(.start)
            let interval = sut.beginInterval("Too late")

            clock.set(start.addingTimeInterval(60))
            sut.endInterval(interval)

            #expect(sut.snapshot.intervals.isEmpty)
            #expect(sut.snapshot.isRecording)
            sut.perform(.stop)
        }

        @Test("Export records the copy with how much it held, while recording only; start again changes nothing")
        func export() throws {
            let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
            let clock = MovableClock(start)
            let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 10, clock: clock, timer: ManualTimer())
            let runLoop = try #require(CFRunLoopGetMain())
            let sut = try PerformanceTraces(
                sessions: sessions, hitchThreshold: .milliseconds(100), hangThreshold: .milliseconds(250), limits: .standard,
                now: { clock.now }, watchedThread: { (runLoop, MachThreadStackSampler.currentThread()) }
            )
            sut.perform(.export)
            let beforeRecording = sut.snapshot.exports
            sessions.perform(.open(duration: 60))
            sut.perform(.start)
            let monitor = sut.monitor
            sut.endInterval(sut.beginInterval("One"))

            sut.perform(.start)
            sut.perform(.export)

            #expect(beforeRecording.isEmpty)
            #expect(sut.monitor === monitor)
            #expect(sut.snapshot.exports == [PerformanceTraces.Export(date: start, stalls: 0, intervals: 1)])
            sut.perform(.stop)
        }

        @Test("The report text lists each stall's frames, each interval, and the binary images with their load addresses and UUIDs")
        func reportText() throws {
            let uuid = try #require(UUID(uuidString: "6F1C2B0E-8C4D-4E6A-9C0B-1D2E3F405162"))
            let snapshot = PerformanceTraces.Snapshot(
                sessionID: UUID(), executable: "Example", hitchThreshold: .milliseconds(100), hangThreshold: .milliseconds(250),
                stalls: [
                    PerformanceTraces.Stall(
                        id: 1, kind: .hang, began: Date(timeIntervalSince1970: 0), duration: .milliseconds(2013),
                        frames: [
                            PerformanceTraces.Frame(address: 0x1_0000_4A1C, image: "Example", imageUUID: uuid, imageOffset: 0x4A1C),
                            PerformanceTraces.Frame(address: 0x10)
                        ]
                    )
                ],
                intervals: [
                    PerformanceTraces.SignpostInterval(id: 1, name: "Load feed", began: Date(timeIntervalSince1970: 1), duration: .milliseconds(340))
                ],
                droppedStalls: 0, droppedIntervals: 2, limits: .standard, exports: []
            )

            let actual = snapshot.text

            let expected = """
            Hitch threshold: 100 ms, hang threshold: 250 ms

            Stalls (1, 0 dropped)

            Hang #1: 2013 ms at 1970-01-01T00:00:00Z
            0 Example 0x0000000100004a1c
            1 ??? 0x0000000000000010

            Signpost intervals (1, 2 dropped)

            Load feed: 340 ms at 1970-01-01T00:00:01Z

            Binary images

            0x0000000100000000 Example <6F1C2B0E-8C4D-4E6A-9C0B-1D2E3F405162>

            """
            #expect(actual == expected)
        }
    }
#endif
