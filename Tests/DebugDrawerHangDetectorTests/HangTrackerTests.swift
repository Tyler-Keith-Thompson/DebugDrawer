import DebugDrawerHangDetector
import Testing

@Suite
struct HangTrackerTests {
    @Test("Nothing counts until the run loop first waits: the first pass is the launch")
    func launchIgnored() {
        let start = SuspendingClock.Instant.now
        var sut = HangTracker(threshold: .milliseconds(250))

        let entry = sut.checkpoint(at: start, isAboutToWait: false)
        let sources = sut.checkpoint(at: start + .seconds(2), isAboutToWait: false)
        let wait = sut.checkpoint(at: start + .seconds(4), isAboutToWait: true)

        #expect(entry == nil)
        #expect(sources == nil)
        #expect(wait == nil)
        #expect(sut.phase == .waiting)
    }

    @Test("A stretch at least the threshold long ends as a hang of its length, uncaptured without a tick")
    func hang() {
        let start = SuspendingClock.Instant.now
        var sut = HangTracker(threshold: .milliseconds(250))
        _ = sut.checkpoint(at: start, isAboutToWait: true)
        _ = sut.checkpoint(at: start + .milliseconds(10), isAboutToWait: false)
        let expected = HangTracker.Hang(duration: .milliseconds(612), isCaptured: false)

        let actual = sut.checkpoint(at: start + .milliseconds(622), isAboutToWait: true)

        #expect(actual == expected)
        #expect(sut.phase == .waiting)
    }

    @Test("A stretch exactly the threshold long is a hang; one a nanosecond shorter isn't")
    func boundary() {
        let start = SuspendingClock.Instant.now
        let threshold = Duration.milliseconds(250)
        var sut = HangTracker(threshold: threshold)
        _ = sut.checkpoint(at: start, isAboutToWait: true)
        _ = sut.checkpoint(at: start, isAboutToWait: false)

        let short = sut.checkpoint(at: start + threshold - .nanoseconds(1), isAboutToWait: false)
        let exact = sut.checkpoint(at: start + threshold - .nanoseconds(1) + threshold, isAboutToWait: false)

        #expect(short == nil)
        #expect(exact == HangTracker.Hang(duration: threshold, isCaptured: false))
    }

    @Test("Each checkpoint that isn't a wait ends one stretch and begins the next")
    func stretchesRestart() {
        let start = SuspendingClock.Instant.now
        var sut = HangTracker(threshold: .milliseconds(250))
        _ = sut.checkpoint(at: start, isAboutToWait: true)
        _ = sut.checkpoint(at: start, isAboutToWait: false)

        let first = sut.checkpoint(at: start + .milliseconds(200), isAboutToWait: false)
        let second = sut.checkpoint(at: start + .milliseconds(400), isAboutToWait: false)

        #expect(first == nil)
        #expect(second == nil)
        #expect(sut.phase == .busy(since: start + .milliseconds(400), isCaptured: false))
    }

    @Test("Time spent waiting is never a hang")
    func waitingIsIdle() {
        let start = SuspendingClock.Instant.now
        var sut = HangTracker(threshold: .milliseconds(250))
        _ = sut.checkpoint(at: start, isAboutToWait: true)

        let tick = sut.tick(at: start + .seconds(10))
        let actual = sut.checkpoint(at: start + .seconds(10), isAboutToWait: false)

        #expect(!tick)
        #expect(actual == nil)
    }

    @Test("The watcher captures once per hang, as soon as the stretch reaches the threshold")
    func captureOnce() {
        let start = SuspendingClock.Instant.now
        var sut = HangTracker(threshold: .milliseconds(200))
        _ = sut.checkpoint(at: start, isAboutToWait: true)
        _ = sut.checkpoint(at: start, isAboutToWait: false)
        let expectedTicks = [false, false, false, true, false, false]

        let actualTicks = [50, 100, 150, 200, 250, 300].map { sut.tick(at: start + .milliseconds($0)) }
        let actual = sut.checkpoint(at: start + .milliseconds(320), isAboutToWait: true)

        #expect(actualTicks == expectedTicks)
        #expect(actual == HangTracker.Hang(duration: .milliseconds(320), isCaptured: true))
    }

    @Test("The next stretch starts uncaptured, so its hang is captured again")
    func captureAgain() {
        let start = SuspendingClock.Instant.now
        var sut = HangTracker(threshold: .milliseconds(100))
        _ = sut.checkpoint(at: start, isAboutToWait: true)
        _ = sut.checkpoint(at: start, isAboutToWait: false)
        _ = sut.tick(at: start + .milliseconds(100))
        _ = sut.checkpoint(at: start + .milliseconds(120), isAboutToWait: false)

        let actual = sut.tick(at: start + .milliseconds(220))

        #expect(actual)
    }

    @Test("A threshold changed during a stretch applies when it ends")
    func thresholdChange() {
        let start = SuspendingClock.Instant.now
        var sut = HangTracker(threshold: .milliseconds(1000))
        _ = sut.checkpoint(at: start, isAboutToWait: true)
        _ = sut.checkpoint(at: start, isAboutToWait: false)

        sut.threshold = .milliseconds(100)
        let actual = sut.checkpoint(at: start + .milliseconds(150), isAboutToWait: true)

        #expect(actual == HangTracker.Hang(duration: .milliseconds(150), isCaptured: false))
    }

    @Test("The watcher wakes four times per threshold")
    func tickInterval() {
        let sut = HangTracker(threshold: .milliseconds(250))

        let actual = sut.tickInterval

        #expect(actual == .microseconds(62500))
    }

    @Test("A watcher that wakes more than a threshold and a tick late was stopped with the process: the stretch restarts")
    func stoppedAtTick() {
        let start = SuspendingClock.Instant.now
        var sut = HangTracker(threshold: .milliseconds(100))
        _ = sut.checkpoint(at: start, isAboutToWait: true)
        _ = sut.tick(at: start)
        _ = sut.checkpoint(at: start + .milliseconds(10), isAboutToWait: false)

        let late = sut.tick(at: start + .seconds(30))
        let actual = sut.checkpoint(at: start + .seconds(30) + .milliseconds(20), isAboutToWait: true)

        #expect(!late)
        #expect(actual == nil)
    }

    @Test("A stretch that ends after the watcher missed its ticks isn't a hang: the process was stopped")
    func stoppedAtCheckpoint() {
        let start = SuspendingClock.Instant.now
        var sut = HangTracker(threshold: .milliseconds(100))
        _ = sut.checkpoint(at: start, isAboutToWait: true)
        _ = sut.tick(at: start)
        _ = sut.checkpoint(at: start + .milliseconds(10), isAboutToWait: false)

        let actual = sut.checkpoint(at: start + .seconds(30), isAboutToWait: true)

        #expect(actual == nil)
    }

    @Test("A watcher a little late, within a threshold and a tick, still sees the hang")
    func lateTickStillCounts() {
        let start = SuspendingClock.Instant.now
        var sut = HangTracker(threshold: .milliseconds(100))
        _ = sut.checkpoint(at: start, isAboutToWait: true)
        _ = sut.tick(at: start)
        _ = sut.checkpoint(at: start, isAboutToWait: false)

        let tick = sut.tick(at: start + .milliseconds(125))
        let actual = sut.checkpoint(at: start + .milliseconds(130), isAboutToWait: true)

        #expect(tick)
        #expect(actual == HangTracker.Hang(duration: .milliseconds(130), isCaptured: true))
    }

    @Test("A stretch the tracker is paused in is no hang, however long, even one already captured")
    func pausedStretchDropped() {
        let start = SuspendingClock.Instant.now
        var sut = HangTracker(threshold: .milliseconds(100))
        _ = sut.checkpoint(at: start, isAboutToWait: true)
        _ = sut.checkpoint(at: start, isAboutToWait: false)
        let captured = sut.tick(at: start + .milliseconds(100))

        sut.pause()
        let actual = sut.checkpoint(at: start + .milliseconds(110), isAboutToWait: true)

        #expect(captured)
        #expect(actual == nil)
        #expect(sut.isPaused)
    }

    @Test("While paused, stretches are no hangs and the watcher captures nothing")
    func pausedNothingCounts() {
        let start = SuspendingClock.Instant.now
        var sut = HangTracker(threshold: .milliseconds(100))
        _ = sut.checkpoint(at: start, isAboutToWait: true)
        sut.pause()
        _ = sut.checkpoint(at: start, isAboutToWait: false)

        let ticks = [25, 50, 75, 100, 125].map { sut.tick(at: start + .milliseconds($0)) }
        let actual = sut.checkpoint(at: start + .milliseconds(130), isAboutToWait: true)

        #expect(ticks.allSatisfy { !$0 })
        #expect(actual == nil)
    }

    @Test("Resumed during a stretch, the stretch counts from the resume")
    func resumeRestartsStretch() {
        let start = SuspendingClock.Instant.now
        var sut = HangTracker(threshold: .milliseconds(100))
        _ = sut.checkpoint(at: start, isAboutToWait: true)
        sut.pause()
        _ = sut.checkpoint(at: start, isAboutToWait: false)
        sut.resume(at: start + .milliseconds(500))
        let expected = HangTracker.Hang(duration: .milliseconds(120), isCaptured: false)

        let actual = sut.checkpoint(at: start + .milliseconds(620), isAboutToWait: true)

        #expect(actual == expected)
        #expect(!sut.isPaused)
    }

    @Test("Resumed while waiting, the next stretch counts as usual; resuming twice changes nothing")
    func resumeWhileWaiting() {
        let start = SuspendingClock.Instant.now
        var sut = HangTracker(threshold: .milliseconds(100))
        _ = sut.checkpoint(at: start, isAboutToWait: true)
        sut.pause()
        sut.resume(at: start + .milliseconds(10))
        _ = sut.checkpoint(at: start + .milliseconds(20), isAboutToWait: false)
        sut.resume(at: start + .milliseconds(90))
        let expected = HangTracker.Hang(duration: .milliseconds(150), isCaptured: false)

        let actual = sut.checkpoint(at: start + .milliseconds(170), isAboutToWait: true)

        #expect(actual == expected)
    }
}
