// What the leak detector adds to each turn of the main run loop. The detector exists in debug
// builds only, so it is measured there; `--config=release` builds this target without it, and runs
// ReleaseInstallTests instead.
#if DEBUG
    @testable import DebugDrawerLeakDetectorPlugin
    import Foundation
    import Testing

    // Measured on an Apple silicon Mac in debug builds (`bazel test`, `swift test`): a turn with
    // nothing dismissed is one check of an empty dictionary, well under 0.1 µs; a turn that
    // rechecks ten flagged view controllers costs a few microseconds. The bounds are several times
    // those figures, so a loaded machine passes and a change that makes an idle turn do real work
    // (allocate, sort, publish) fails.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct LeakDetectorOverheadTests {
        /// Turns the test ends by hand.
        final class ManualTurns: RunLoopTurnSource {
            var onTurnEnd: (@MainActor () -> Void)?

            func observe(_ onTurnEnd: @escaping @MainActor () -> Void) {
                self.onTurnEnd = onTurnEnd
            }

            func wakeUp() {}
        }

        @Test("A turn with nothing dismissed costs under 1 µs")
        func idleTurnCost() throws {
            let turns = ManualTurns()
            let sut = LeakMonitor(turns: turns) { _ in }
            let endTurn = try #require(turns.onTurnEnd)
            let iterations = 500_000
            let clock = ContinuousClock()

            let elapsed = clock.measure {
                for _ in 0 ..< iterations {
                    endTurn()
                }
            }
            let actual = elapsed / iterations

            print("Leak detector: an idle turn costs \(actual) with \(sut.suspects.count) suspects")
            #expect(actual < .microseconds(1))
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
            let iterations = 20000
            let clock = ContinuousClock()

            let elapsed = clock.measure {
                for _ in 0 ..< iterations {
                    endTurn()
                }
            }
            let actual = elapsed / iterations

            print("Leak detector: a turn with \(screens.count) flagged view controllers costs \(actual)")
            #expect(sut.suspects.map(\.count) == [10])
            #expect(actual < .microseconds(100))
        }
    }
#endif
