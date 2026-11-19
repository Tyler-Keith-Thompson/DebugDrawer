#if DEBUG
    import Combine
    import Darwin
    import DebugDrawer
    @testable import DebugDrawerPerformancePlugin
    import Foundation
    import Testing

    /// Stands in for the display link and the 1 s timer: records starts and stops, and delivers
    /// the frames and ticks the test hands it while it runs.
    @MainActor
    private final class FakeSampler: PerformanceSampler {
        private(set) var starts = 0
        private(set) var stops = 0
        private var frame: (@MainActor (TimeInterval, TimeInterval) -> Void)?
        private var tick: (@MainActor () -> Void)?

        var isRunning: Bool {
            tick != nil
        }

        func start(
            frame: @escaping @MainActor (TimeInterval, TimeInterval) -> Void,
            tick: @escaping @MainActor () -> Void
        ) {
            starts += 1
            self.frame = frame
            self.tick = tick
        }

        func stop() {
            stops += 1
            frame = nil
            tick = nil
        }

        /// Delivers `count` frames a frame period apart from `start`, as a smooth display would.
        func deliverFrames(from start: TimeInterval, count: Int, duration: TimeInterval = 1.0 / 60) {
            for index in 0 ..< count {
                frame?(start + TimeInterval(index) * duration, duration)
            }
        }

        func deliverTick() {
            tick?()
        }
    }

    /// A process with the threads the test gives it; counts its readings.
    private final class FakeThreads: ThreadSampler {
        var threads: [ThreadCPU]
        private(set) var reads = 0

        init(_ threads: [ThreadCPU] = []) {
            self.threads = threads
        }

        func sample() -> [ThreadCPU] {
            reads += 1
            return threads
        }
    }

    /// A kernel that reports the footprint and peak the test gives it, in MiB; counts its readings.
    private final class FakeMemory: TaskVMInfoSource {
        var footprintMB: UInt64
        var peakMB: UInt64
        private(set) var reads = 0

        init(footprintMB: UInt64 = 0, peakMB: UInt64 = 0) {
            self.footprintMB = footprintMB
            self.peakMB = peakMB
        }

        func taskVMInfo() -> task_vm_info_data_t? {
            reads += 1
            var info = task_vm_info_data_t()
            info.phys_footprint = footprintMB * 1024 * 1024
            info.ledger_phys_footprint_peak = Int64(peakMB * 1024 * 1024)
            return info
        }
    }

    /// Posts no notification: records each post and answers with a fixed time.
    @MainActor
    private final class FakeMemoryWarning: MemoryWarningPoster {
        let postedAt: Date
        private(set) var posts = 0

        init(postedAt: Date) {
            self.postedAt = postedAt
        }

        func postMemoryWarning() -> Date {
            posts += 1
            return postedAt
        }
    }

    @MainActor
    @Suite("Performance's model, driven through commands over fake samplers", .timeLimit(.minutes(1)))
    struct PerformanceModelTests {
        @Test("A snapshot with readings, history, threads and a posted warning comes back equal from JSON")
        func snapshotRoundTrips() throws {
            let expected = PerformanceSnapshot(
                isMonitoring: true,
                fps: 58,
                maximumFPS: 120,
                droppedFrames: 7,
                fpsHistory: [60, 58, 31],
                footprintMB: 182.4,
                footprintHistory: [180.5, 181, 182.4],
                peakFootprintMB: 240.25,
                physicalMemoryMB: 16384,
                historyLength: 30,
                threads: [
                    ThreadCPU(name: "Main Thread", threadID: 1, cpuUsage: 0.42),
                    ThreadCPU(name: "com.apple.NSURLSession-work", threadID: 0xA2F, cpuUsage: 0)
                ],
                memoryWarningPostedAt: Date(timeIntervalSince1970: 1_700_000_000)
            )

            let actual = try JSONDecoder().decode(PerformanceSnapshot.self, from: JSONEncoder().encode(expected))

            #expect(actual == expected)
        }

        @Test("Every command comes back from JSON as the same action")
        func commandsRoundTrip() throws {
            let expected: [PerformanceCommand.Action] = [
                .start, .stop, .reset, .setHistoryLength(30), .simulateMemoryWarning
            ]

            let actual = try expected.map {
                try JSONDecoder().decode(PerformanceCommand.self, from: JSONEncoder().encode(PerformanceCommand($0))).action
            }

            #expect(actual == expected)
        }

        @Test("A new model reads nothing and starts nothing; its snapshot holds only the device's memory")
        func nothingBeforeStart() {
            let sampler = FakeSampler()
            let threads = FakeThreads([ThreadCPU(name: "Main Thread", threadID: 1, cpuUsage: 0.5)])
            let memory = FakeMemory(footprintMB: 100, peakMB: 150)
            let expected = PerformanceSnapshot(physicalMemoryMB: 8192)

            let sut = PerformanceModel(sampler: sampler, threadSampler: threads, memory: memory, physicalMemory: 8192 * 1024 * 1024)

            #expect(sut.snapshot == expected)
            #expect(sampler.starts == 0)
            #expect(threads.reads == 0)
            #expect(memory.reads == 0)
        }

        @Test("Start reads memory and threads at once; each second sums up its frames and samples both again")
        func samplesAreSummarised() {
            let sampler = FakeSampler()
            let threads = FakeThreads([ThreadCPU(name: "Main Thread", threadID: 1, cpuUsage: 0.25)])
            let memory = FakeMemory(footprintMB: 100, peakMB: 150)
            let sut = PerformanceModel(sampler: sampler, threadSampler: threads, memory: memory, physicalMemory: 0)
            let transport = DebugDrawerPluginTransport.direct(to: sut)

            transport.send(PerformanceCommand(.start))
            let afterStart = transport.snapshot
            sampler.deliverFrames(from: 10, count: 61)
            memory.footprintMB = 120
            sampler.deliverTick()
            // Half a second with no frame: 29 periods skipped.
            sampler.deliverFrames(from: 11 + 0.5, count: 31)
            memory.footprintMB = 130
            memory.peakMB = 200
            sampler.deliverTick()
            let actual = transport.snapshot

            #expect(afterStart.isMonitoring)
            #expect(afterStart.footprintMB == 100)
            #expect(afterStart.peakFootprintMB == 150)
            #expect(afterStart.threads == threads.threads)
            #expect(afterStart.fpsHistory.isEmpty)
            #expect(actual.fpsHistory == [60, 31])
            #expect(actual.fps == 31)
            #expect(actual.maximumFPS == 60)
            #expect(actual.droppedFrames == 29)
            #expect(actual.footprintHistory == [120, 130])
            #expect(actual.footprintMB == 130)
            #expect(actual.peakFootprintMB == 200)
            #expect(threads.reads == 3)
            #expect(memory.reads == 3)
        }

        @Test("A tick changes the snapshot once, so a view redraws once a second")
        func oneChangePerTick() {
            let sampler = FakeSampler()
            let sut = PerformanceModel(sampler: sampler, threadSampler: FakeThreads(), memory: FakeMemory(), physicalMemory: 0)
            sut.perform(PerformanceCommand(.start))
            sampler.deliverFrames(from: 0, count: 61)
            var changes = 0
            let subscription = sut.objectWillChange.sink { changes += 1 }

            sampler.deliverTick()

            subscription.cancel()
            #expect(changes == 1)
        }

        @Test("Stop stops the sampler, and nothing is read after it: ticks and frames from a stopped sampler change nothing")
        func nothingAfterStop() {
            let sampler = FakeSampler()
            let threads = FakeThreads()
            let memory = FakeMemory(footprintMB: 100, peakMB: 100)
            let sut = PerformanceModel(sampler: sampler, threadSampler: threads, memory: memory, physicalMemory: 0)
            sut.perform(PerformanceCommand(.start))
            sampler.deliverFrames(from: 0, count: 61)
            sampler.deliverTick()
            let readsBeforeStop = (threads.reads, memory.reads)

            sut.perform(PerformanceCommand(.stop))
            let snapshotAtStop = sut.snapshot
            sampler.deliverFrames(from: 1, count: 60)
            sampler.deliverTick()

            #expect(sampler.starts == 1)
            #expect(sampler.stops == 1)
            #expect(!sampler.isRunning)
            #expect(!sut.snapshot.isMonitoring)
            #expect(threads.reads == readsBeforeStop.0)
            #expect(memory.reads == readsBeforeStop.1)
            #expect(sut.snapshot == snapshotAtStop)
            #expect(sut.snapshot.fpsHistory == [60])
        }

        @Test("Start and stop count readers: a second start doesn't restart, a stop with none counted does nothing")
        func startAndStopCount() {
            let sampler = FakeSampler()
            let sut = PerformanceModel(sampler: sampler, threadSampler: FakeThreads(), memory: FakeMemory(), physicalMemory: 0)

            sut.perform(PerformanceCommand(.stop))
            sut.perform(PerformanceCommand(.start))
            sut.perform(PerformanceCommand(.start))
            sut.perform(PerformanceCommand(.stop))
            let runningWithOneLeft = sampler.isRunning
            sut.perform(PerformanceCommand(.stop))

            #expect(runningWithOneLeft)
            #expect(sampler.starts == 1)
            #expect(sampler.stops == 1)
            #expect(!sut.snapshot.isMonitoring)
        }

        @Test("A reader's start shares the sampler with a drawer's viewer: the drawer hiding the plugin leaves it running")
        func commandsShareTheViewerCount() {
            let sampler = FakeSampler()
            let sut = PerformanceModel(sampler: sampler, threadSampler: FakeThreads(), memory: FakeMemory(), physicalMemory: 0)

            sut.addViewer()
            sut.perform(PerformanceCommand(.start))
            sut.removeViewer()

            #expect(sampler.isRunning)
            #expect(sampler.starts == 1)
        }

        @Test("Reset drops the history and the frames dropped, keeps sampling, and the next second starts the history again")
        func reset() {
            let sampler = FakeSampler()
            let memory = FakeMemory(footprintMB: 100, peakMB: 150)
            let sut = PerformanceModel(sampler: sampler, threadSampler: FakeThreads(), memory: memory, physicalMemory: 0)
            sut.perform(PerformanceCommand(.start))
            sampler.deliverFrames(from: 0, count: 16)
            sampler.deliverFrames(from: 0.75, count: 16)
            sampler.deliverTick()
            let droppedBeforeReset = sut.snapshot.droppedFrames

            sut.perform(PerformanceCommand(.reset))
            let afterReset = sut.snapshot
            sampler.deliverFrames(from: 1, count: 60)
            sampler.deliverTick()

            #expect(droppedBeforeReset == 29)
            #expect(afterReset.fpsHistory.isEmpty)
            #expect(afterReset.footprintHistory.isEmpty)
            #expect(afterReset.droppedFrames == 0)
            #expect(afterReset.isMonitoring)
            #expect(afterReset.peakFootprintMB == 150)
            #expect(sut.snapshot.fpsHistory.count == 1)
            #expect(sut.snapshot.footprintHistory == [100])
            #expect(sampler.stops == 0)
        }

        @Test("The history keeps the last historyLength seconds; a shorter length trims it, and a length below one keeps one")
        func historyLength() {
            let sampler = FakeSampler()
            let memory = FakeMemory()
            let sut = PerformanceModel(sampler: sampler, threadSampler: FakeThreads(), memory: memory, physicalMemory: 0)
            sut.perform(PerformanceCommand(.setHistoryLength(3)))
            sut.perform(PerformanceCommand(.start))
            for second in 1 ... 5 {
                memory.footprintMB = UInt64(second)
                sampler.deliverTick()
            }
            let afterFive = sut.snapshot

            sut.perform(PerformanceCommand(.setHistoryLength(2)))
            let afterShortening = sut.snapshot
            sut.perform(PerformanceCommand(.setHistoryLength(0)))

            #expect(PerformanceSnapshot().historyLength == 60)
            #expect(afterFive.historyLength == 3)
            #expect(afterFive.footprintHistory == [3, 4, 5])
            #expect(afterFive.fpsHistory.count == 3)
            #expect(afterShortening.footprintHistory == [4, 5])
            #expect(sut.snapshot.historyLength == 1)
            #expect(sut.snapshot.footprintHistory == [5])
        }

        @Test("Commands land in the order sent, each before send returns")
        func commandOrder() {
            let firstSampler = FakeSampler()
            let secondSampler = FakeSampler()
            let first = PerformanceModel(sampler: firstSampler, threadSampler: FakeThreads(), memory: FakeMemory(), physicalMemory: 0)
            let second = PerformanceModel(sampler: secondSampler, threadSampler: FakeThreads(), memory: FakeMemory(), physicalMemory: 0)
            let firstTransport = DebugDrawerPluginTransport.direct(to: first)
            let secondTransport = DebugDrawerPluginTransport.direct(to: second)

            firstTransport.send(PerformanceCommand(.setHistoryLength(5)))
            firstTransport.send(PerformanceCommand(.setHistoryLength(1)))
            firstTransport.send(PerformanceCommand(.start))
            firstTransport.send(PerformanceCommand(.stop))
            secondTransport.send(PerformanceCommand(.setHistoryLength(1)))
            secondTransport.send(PerformanceCommand(.setHistoryLength(5)))
            secondTransport.send(PerformanceCommand(.stop))
            secondTransport.send(PerformanceCommand(.start))

            #expect(firstTransport.snapshot.historyLength == 1)
            #expect(!firstTransport.snapshot.isMonitoring)
            #expect(!firstSampler.isRunning)
            #expect(secondTransport.snapshot.historyLength == 5)
            #expect(secondTransport.snapshot.isMonitoring)
            #expect(secondSampler.isRunning)
        }

        @Test("Simulate Memory Warning posts once through the poster and records when; with no poster it does nothing")
        func memoryWarning() {
            let postedAt = Date(timeIntervalSince1970: 1_700_000_000)
            let poster = FakeMemoryWarning(postedAt: postedAt)
            let sut = PerformanceModel(
                sampler: FakeSampler(), threadSampler: FakeThreads(), memory: FakeMemory(), physicalMemory: 0, memoryWarning: poster
            )
            let mac = PerformanceModel(
                sampler: FakeSampler(), threadSampler: FakeThreads(), memory: FakeMemory(), physicalMemory: 0, memoryWarning: nil
            )

            sut.perform(PerformanceCommand(.simulateMemoryWarning))
            mac.perform(PerformanceCommand(.simulateMemoryWarning))

            #expect(poster.posts == 1)
            #expect(sut.snapshot.memoryWarningPostedAt == postedAt)
            #expect(mac.snapshot.memoryWarningPostedAt == nil)
        }

        @Test("Installed in two drawers, a stranger's uninstall and the first drawer's keep everything; the last one stops and drops it")
        func installCounting() {
            let sampler = FakeSampler()
            let sut = PerformanceModel(
                sampler: sampler, threadSampler: FakeThreads(), memory: FakeMemory(footprintMB: 100, peakMB: 100), physicalMemory: 1024 * 1024 * 1024,
                memoryWarning: FakeMemoryWarning(postedAt: Date(timeIntervalSince1970: 0))
            )
            let firstDrawer = NSObject()
            let secondDrawer = NSObject()
            let stranger = NSObject()
            sut.install(in: ObjectIdentifier(firstDrawer))
            sut.install(in: ObjectIdentifier(secondDrawer))
            sut.perform(PerformanceCommand(.setHistoryLength(10)))
            sut.addViewer()
            sampler.deliverFrames(from: 0, count: 61)
            sampler.deliverTick()
            sut.perform(PerformanceCommand(.simulateMemoryWarning))

            sut.uninstall(from: ObjectIdentifier(stranger))
            sut.uninstall(from: ObjectIdentifier(firstDrawer))
            let withOneDrawerLeft = sut.snapshot
            let runningWithOneDrawerLeft = sampler.isRunning
            sut.uninstall(from: ObjectIdentifier(secondDrawer))

            #expect(runningWithOneDrawerLeft)
            #expect(withOneDrawerLeft.fpsHistory == [60])
            #expect(withOneDrawerLeft.memoryWarningPostedAt != nil)
            #expect(!sampler.isRunning)
            #expect(sampler.stops == 1)
            #expect(sut.snapshot == PerformanceSnapshot(maximumFPS: 60, physicalMemoryMB: 1024, historyLength: 10))
        }
    }
#endif
