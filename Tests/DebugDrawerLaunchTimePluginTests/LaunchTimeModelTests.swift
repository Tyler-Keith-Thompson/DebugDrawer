#if DEBUG
    import DebugDrawer
    @testable import DebugDrawerLaunchTimePlugin
    import Foundation
    import Testing

    /// A clock the test moves by hand.
    private final class FakeClock: UptimeClock {
        var now: TimeInterval
        init(_ now: TimeInterval) { self.now = now }
        var uptime: TimeInterval { now }
    }

    /// A process that started at `uptime`, or one whose start can't be read.
    private struct FakeProcessStart: ProcessStartReader {
        let uptime: TimeInterval?
        func processStartUptime() -> TimeInterval? { uptime }
    }

    /// A first frame the test brings in by hand: it keeps the handler it is given and counts how
    /// often it starts and stops waiting.
    @MainActor
    private final class FakeFirstFrameObserver: FirstFrameObserver {
        private var handler: (@MainActor @Sendable () -> Void)?
        private(set) var startCount = 0
        private(set) var stopCount = 0

        var isWaiting: Bool { handler != nil }

        func start(_ handler: @escaping @MainActor @Sendable () -> Void) {
            startCount += 1
            self.handler = handler
        }

        func stop() {
            stopCount += 1
            handler = nil
        }

        /// The first frame is in: calls the handler, if anything waits.
        func bringInFirstFrame() {
            handler?()
        }
    }

    // The model is read and driven here as an out-of-process reader would: through its snapshot,
    // encoded and decoded, and commands, encoded and decoded, with no view. Its clock, the process
    // start and the first frame are fakes; nothing reads the kernel or the main run loop.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct LaunchTimeModelTests {
        @Test("A measured launch's snapshot encodes to JSON and decodes equal")
        func measuredSnapshotRoundTrips() throws {
            let clock = FakeClock(100.4)
            let sut = LaunchTimeModel(clock: clock, processStart: FakeProcessStart(uptime: 100), firstFrameObserver: FakeFirstFrameObserver())
            clock.now = 100.9
            sut.perform(LaunchTimeCommand(.recordFirstFrame))
            let expected = LaunchTimeSnapshot(processStartUptime: 100, appInitUptime: 100.4, firstFrameUptime: 100.9)

            let encoded = try JSONEncoder().encode(sut.snapshot)
            let actual = try JSONDecoder().decode(LaunchTimeSnapshot.self, from: encoded)

            #expect(actual == expected)
            #expect(abs((actual.totalLaunchTime ?? 0) - 0.9) <= 1e-9)
            #expect(abs((actual.preMainDuration ?? 0) - 0.4) <= 1e-9)
            #expect(abs((actual.appInitToFirstFrame ?? 0) - 0.5) <= 1e-9)
        }

        @Test("A snapshot still measuring, with no process start, encodes to JSON and decodes equal")
        func measuringSnapshotRoundTrips() throws {
            let sut = LaunchTimeModel(clock: FakeClock(7), processStart: FakeProcessStart(uptime: nil), firstFrameObserver: FakeFirstFrameObserver())
            let expected = LaunchTimeSnapshot(processStartUptime: nil, appInitUptime: 7, firstFrameUptime: nil)

            let encoded = try JSONEncoder().encode(sut.snapshot)
            let actual = try JSONDecoder().decode(LaunchTimeSnapshot.self, from: encoded)

            #expect(actual == expected)
            #expect(actual.preMainDuration == nil)
            #expect(actual.appInitToFirstFrame == nil)
            #expect(actual.totalLaunchTime == nil)
        }

        @Test("Record First Frame, encoded to JSON and decoded, records the clock's time through a direct transport and stops waiting")
        func recordFirstFrameCommandRoundTrips() throws {
            let clock = FakeClock(10)
            let firstFrame = FakeFirstFrameObserver()
            let model = LaunchTimeModel(clock: clock, processStart: FakeProcessStart(uptime: 9), firstFrameObserver: firstFrame)
            let drawer = DebugDrawer()
            model.install(in: ObjectIdentifier(drawer))
            let sut = DebugDrawerPluginTransport.direct(to: model)
            clock.now = 10.75
            let command = LaunchTimeCommand(.recordFirstFrame)

            let decoded = try JSONDecoder().decode(LaunchTimeCommand.self, from: JSONEncoder().encode(command))
            sut.send(decoded)

            #expect(sut.snapshot.firstFrameUptime == 10.75)
            #expect(model.firstFrameUptime == 10.75)
            #expect(!firstFrame.isWaiting)
            #expect(firstFrame.stopCount == 1)
        }

        @Test("Installing waits for the first frame; when it comes, the clock's time is recorded and later frames don't move it")
        func installRecordsTheFirstFrame() {
            let clock = FakeClock(50)
            let firstFrame = FakeFirstFrameObserver()
            let sut = LaunchTimeModel(clock: clock, processStart: FakeProcessStart(uptime: 49), firstFrameObserver: firstFrame)
            let drawer = DebugDrawer()
            sut.install(in: ObjectIdentifier(drawer))
            let wasWaiting = firstFrame.isWaiting
            clock.now = 50.25

            firstFrame.bringInFirstFrame()
            clock.now = 99
            sut.perform(LaunchTimeCommand(.recordFirstFrame))
            sut.install(in: ObjectIdentifier(drawer))

            #expect(wasWaiting)
            #expect(sut.snapshot.firstFrameUptime == 50.25)
            #expect(!firstFrame.isWaiting)
            #expect(firstFrame.startCount == 1)
        }

        @Test("Opening the drawer late doesn't change the times: the snapshot reads the same at any later time")
        func snapshotDoesNotMoveWithTheClock() {
            let clock = FakeClock(100.4)
            let sut = LaunchTimeModel(clock: clock, processStart: FakeProcessStart(uptime: 100), firstFrameObserver: FakeFirstFrameObserver())
            clock.now = 100.9
            sut.perform(LaunchTimeCommand(.recordFirstFrame))
            let expected = sut.snapshot

            clock.now = 400
            let actual = sut.snapshot

            #expect(actual == expected)
        }

        @Test("In two drawers the model waits until the last one uninstalls; uninstalling twice is harmless; installing again waits again")
        func twoDrawers() {
            let firstFrame = FakeFirstFrameObserver()
            let sut = LaunchTimeModel(clock: FakeClock(10), processStart: FakeProcessStart(uptime: 9), firstFrameObserver: firstFrame)
            let first = DebugDrawer()
            let second = DebugDrawer()
            sut.install(in: ObjectIdentifier(first))
            sut.install(in: ObjectIdentifier(second))

            sut.uninstall(from: ObjectIdentifier(first))
            let isWaitingWithOneLeft = firstFrame.isWaiting
            sut.uninstall(from: ObjectIdentifier(second))
            sut.uninstall(from: ObjectIdentifier(second))
            let isWaitingWithNone = firstFrame.isWaiting
            sut.install(in: ObjectIdentifier(first))

            #expect(isWaitingWithOneLeft)
            #expect(!isWaitingWithNone)
            #expect(firstFrame.stopCount == 1)
            #expect(firstFrame.isWaiting)
            #expect(firstFrame.startCount == 2)
            #expect(sut.snapshot.firstFrameUptime == nil)
        }

        @Test("Uninstalling after the first frame keeps the times measured, and installing again doesn't wait")
        func uninstallKeepsTimes() {
            let clock = FakeClock(10)
            let firstFrame = FakeFirstFrameObserver()
            let sut = LaunchTimeModel(clock: clock, processStart: FakeProcessStart(uptime: 9), firstFrameObserver: firstFrame)
            let drawer = DebugDrawer()
            sut.install(in: ObjectIdentifier(drawer))
            clock.now = 10.5
            firstFrame.bringInFirstFrame()
            let expected = LaunchTimeSnapshot(processStartUptime: 9, appInitUptime: 10, firstFrameUptime: 10.5)

            sut.uninstall(from: ObjectIdentifier(drawer))
            sut.install(in: ObjectIdentifier(drawer))

            #expect(sut.snapshot == expected)
            #expect(!firstFrame.isWaiting)
            #expect(firstFrame.startCount == 1)
        }

        @Test("A recorded first frame reaches a direct transport's snapshot and its stream")
        func firstFrameReachesTheTransport() async {
            let clock = FakeClock(20)
            let firstFrame = FakeFirstFrameObserver()
            let model = LaunchTimeModel(clock: clock, processStart: FakeProcessStart(uptime: 19.5), firstFrameObserver: firstFrame)
            model.install(in: ObjectIdentifier(DebugDrawer()))
            let sut = DebugDrawerPluginTransport.direct(to: model)
            let snapshots = sut.snapshots()
            clock.now = 20.3

            firstFrame.bringInFirstFrame()
            var actual: LaunchTimeSnapshot?
            for await snapshot in snapshots where snapshot.firstFrameUptime != nil {
                actual = snapshot
                break
            }

            #expect(actual?.firstFrameUptime == 20.3)
            #expect(sut.snapshot.firstFrameUptime == 20.3)
        }
    }
#endif
