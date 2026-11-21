// What the leak detector adds to each turn of the main run loop. The detector exists in debug
// builds only, so it is measured there; `--config=release` builds this target without it, and runs
// ReleaseInstallTests instead.
#if DEBUG
    @testable import DebugDrawerLeakDetectorPlugin
    import Darwin
    import Testing

    // Each test times its turns in the test thread's CPU time (CLOCK_THREAD_CPUTIME_ID), which stops
    // while the thread is descheduled, so other processes loading the machine don't show up as
    // per-turn cost; the work measured all runs on this thread (ManualTurns ends each turn in the
    // call, and onChange is called in it). It keeps the fastest of several batches, which leaves
    // out a batch slowed by a context switch's cold caches or a stretch on an efficiency core.
    //
    // Measured on an Apple silicon Mac in debug builds (`bazel test`): a turn with nothing
    // dismissed costs about 0.8 µs of CPU time, mostly -Onone's copies and exclusivity checks
    // around one check of an empty dictionary; a turn that rechecks ten flagged view controllers
    // costs about 50 µs. A change that makes an idle turn do real work (allocate, sort, publish)
    // fails the 1 µs bound.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct LeakDetectorOverheadTests {
        /// Turns the test ends by hand.
        final class ManualTurns: RunLoopTurnSource {
            var onTurnEnd: (@MainActor () -> Void)?

            func observe(_ onTurnEnd: @escaping @MainActor () -> Void) {
                self.onTurnEnd = onTurnEnd
            }

            func stop() {
                onTurnEnd = nil
            }

            func wakeUp() {}
        }

        @Test("A turn with nothing dismissed costs under 1 µs")
        func idleTurnCost() throws {
            let turns = ManualTurns()
            let sut = LeakMonitor(turns: turns) { _ in }
            let endTurn = try #require(turns.onTurnEnd)
            let batches = 10
            let turnsPerBatch = 50000
            var fastest = Duration.seconds(1)

            for _ in 0 ..< batches {
                let start = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
                for _ in 0 ..< turnsPerBatch {
                    endTurn()
                }
                let end = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
                fastest = min(fastest, .nanoseconds(end - start) / turnsPerBatch)
            }

            print("Leak detector: an idle turn costs \(fastest) of CPU time with \(sut.suspects.count) suspects")
            #expect(fastest < .microseconds(1))
        }

        @Test("A turn that rechecks ten flagged view controllers costs under 100 µs")
        func flaggedTurnCost() throws {
            final class Screen {}
            let turns = ManualTurns()
            let sut = LeakMonitor(turns: turns) { _ in }
            let screens = (0 ..< 10).map { _ in Screen() }
            for screen in screens {
                sut.dismiss(screen) { _ in true }
            }
            let endTurn = try #require(turns.onTurnEnd)
            endTurn()
            endTurn()
            let batches = 10
            let turnsPerBatch = 2000
            var fastest = Duration.seconds(1)

            for _ in 0 ..< batches {
                let start = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
                for _ in 0 ..< turnsPerBatch {
                    endTurn()
                }
                let end = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
                fastest = min(fastest, .nanoseconds(end - start) / turnsPerBatch)
            }

            print("Leak detector: a turn with \(screens.count) flagged view controllers costs \(fastest) of CPU time")
            #expect(sut.suspects.map(\.count) == [10])
            #expect(fastest < .microseconds(100))
        }
    }
#endif
