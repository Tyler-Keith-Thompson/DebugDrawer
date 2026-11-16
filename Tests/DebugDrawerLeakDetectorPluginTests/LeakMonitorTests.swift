#if DEBUG
    @testable import DebugDrawerLeakDetectorPlugin
    import Dispatch
    import Foundation
    import Testing

    // Real objects and their real deallocation, with the run loop's turns ended by hand. A
    // deallocation reaches the monitor through the main queue, so a test that releases an object
    // waits for a block it adds to the queue after it: the queue runs them in order.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct LeakMonitorTests {
        /// Turns the test ends by hand, counting the wake-ups asked for.
        final class ManualTurns: RunLoopTurnSource {
            var onTurnEnd: (@MainActor () -> Void)?
            var wakeUps = 0

            func observe(_ onTurnEnd: @escaping @MainActor () -> Void) {
                self.onTurnEnd = onTurnEnd
            }

            func wakeUp() {
                wakeUps += 1
            }
        }

        final class ProfileScreen {
            var onRefresh: (() -> Void)?
        }

        final class ProfileModel: Sendable {}

        @Test("A dismissed object still detached at the end of the next turn is flagged, and reported as flagged")
        func flagsSurvivor() throws {
            let turns = ManualTurns()
            var changes: [LeakChange] = []
            let flaggedAt = Date(timeIntervalSince1970: 1_763_290_000)
            let sut = LeakMonitor(turns: turns, now: { flaggedAt }, onChange: { changes.append($0) })
            let screen = ProfileScreen()
            let expected = [LeakSuspect(type: TrackedClass(of: screen), reason: .aliveAfterDismissal, count: 1, since: flaggedAt)]
            let endTurn = try #require(turns.onTurnEnd)

            sut.dismiss(screen) { _ in true }
            endTurn()
            endTurn()

            #expect(sut.suspects == expected)
            #expect(changes == [LeakChange(suspects: expected, flagged: expected)])
        }

        @Test("The turn a dismissal happens in asks the run loop to turn again, and later turns don't")
        func wakesForNextTurn() throws {
            let turns = ManualTurns()
            let sut = LeakMonitor(turns: turns) { _ in }
            let screen = ProfileScreen()
            let endTurn = try #require(turns.onTurnEnd)

            endTurn()
            let idle = turns.wakeUps
            sut.dismiss(screen) { _ in true }
            endTurn()
            let afterDismissal = turns.wakeUps
            endTurn()
            endTurn()

            #expect(idle == 0)
            #expect(afterDismissal == 1)
            #expect(turns.wakeUps == 1)
        }

        @Test("A dismissed object released before the next turn ends is never flagged")
        func releasedInTime() async throws {
            let turns = ManualTurns()
            var changes: [LeakChange] = []
            let sut = LeakMonitor(turns: turns) { changes.append($0) }
            var screen: ProfileScreen? = ProfileScreen()
            let endTurn = try #require(turns.onTurnEnd)

            sut.dismiss(try #require(screen)) { _ in true }
            endTurn()
            screen = nil
            await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
            endTurn()

            #expect(sut.suspects.isEmpty)
            #expect(changes.isEmpty)
        }

        @Test("A dismissed object shown again is not flagged")
        func shownAgain() throws {
            let turns = ManualTurns()
            let sut = LeakMonitor(turns: turns) { _ in }
            let screen = ProfileScreen()
            let endTurn = try #require(turns.onTurnEnd)

            sut.dismiss(screen) { _ in false }
            endTurn()
            endTurn()

            #expect(sut.suspects.isEmpty)
        }

        @Test("A retain cycle keeps a dismissed object flagged until the cycle is broken and it deallocates")
        func cycleBroken() async throws {
            let turns = ManualTurns()
            var changes: [LeakChange] = []
            let sut = LeakMonitor(turns: turns) { changes.append($0) }
            var screen: ProfileScreen? = ProfileScreen()
            // Held only by its own cycle once the test lets go; `unowned` lets the test break it.
            unowned let leaking = try #require(screen)
            leaking.onRefresh = { [screen] in _ = screen }
            let endTurn = try #require(turns.onTurnEnd)
            sut.dismiss(leaking) { _ in true }
            screen = nil
            endTurn()
            endTurn()
            let flagged = sut.suspects.map(\.count)

            leaking.onRefresh = nil
            await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }

            #expect(flagged == [1])
            #expect(sut.suspects.isEmpty)
            #expect(changes.last == LeakChange(suspects: [], flagged: []))
        }

        @Test("Tracking holds no reference: a tracked object deallocates as soon as the app lets go of it")
        func holdsNoReference() {
            let sut = LeakMonitor(turns: ManualTurns()) { _ in }
            var model: ProfileModel? = ProfileModel()
            weak let weakModel = model

            sut.track(model!, maxCount: 1)
            model = nil

            #expect(weakModel == nil)
        }

        @Test("A second tracked object of a class allowed one makes it a suspect, and its deallocation clears it")
        func overLimit() async throws {
            var changes: [LeakChange] = []
            let wentOver = Date(timeIntervalSince1970: 1_763_290_000)
            let sut = LeakMonitor(turns: ManualTurns(), now: { wentOver }, onChange: { changes.append($0) })
            let first = ProfileModel()
            var second: ProfileModel? = ProfileModel()
            let expected = [LeakSuspect(type: TrackedClass(of: first), reason: .overLimit(maxCount: 1), count: 2, since: wentOver)]

            sut.track(first, maxCount: 1)
            sut.track(try #require(second), maxCount: 1)
            let flagged = sut.suspects
            second = nil
            await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }

            #expect(flagged == expected)
            #expect(changes == [LeakChange(suspects: expected, flagged: expected), LeakChange(suspects: [], flagged: [])])
            #expect(sut.suspects.isEmpty)
        }

        @Test("An object tracked twice is counted once")
        func trackedTwice() {
            let sut = LeakMonitor(turns: ManualTurns()) { _ in }
            let model = ProfileModel()

            sut.track(model, maxCount: 1)
            sut.track(model, maxCount: 1)

            #expect(sut.suspects.isEmpty)
        }

        @Test("An object tracked off the main thread is counted once the main queue gets to it")
        func trackedOffMain() async {
            let sut = LeakMonitor(turns: ManualTurns()) { _ in }
            let first = ProfileModel()
            sut.track(first, maxCount: 1)

            let second = await Task.detached {
                let model = ProfileModel()
                sut.track(model, maxCount: 1)
                return model
            }.value
            await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }

            #expect(sut.suspects.map(\.count) == [2])
            withExtendedLifetime(second) {}
        }
    }
#endif
