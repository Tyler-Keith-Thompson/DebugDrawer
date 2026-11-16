#if DEBUG
    @testable import DebugDrawerLeakDetectorPlugin
    import Foundation
    import Testing

    @Suite
    struct LeakTrackerTests {
        @Test("An empty tracker has no suspects, nothing to check and no reason to turn again")
        func empty() {
            let sut = LeakTracker()

            #expect(sut.suspects.isEmpty)
            #expect(sut.dueForCheck.isEmpty)
            #expect(!sut.isWaitingForTurn)
        }

        @Test("A view controller still off screen at the end of the turn after its dismissal is flagged, with the date of that turn")
        func flaggedAfterNextTurn() {
            let screen = TrackedClass(name: "ProfileViewController", qualifiedName: "Example.ProfileViewController")
            let flaggedAt = Date(timeIntervalSince1970: 1_763_290_000)
            let expected = [LeakSuspect(type: screen, reason: .aliveAfterDismissal, count: 1, since: flaggedAt)]
            var sut = LeakTracker()

            sut.dismiss(7, of: screen)
            let sameTurn = sut.endTurn(at: Date(timeIntervalSince1970: 1), detached: [7])
            let dueNextTurn = sut.dueForCheck
            let actual = sut.endTurn(at: flaggedAt, detached: [7])

            #expect(sameTurn.isEmpty)
            #expect(dueNextTurn == [7])
            #expect(actual == expected)
            #expect(sut.suspects == expected)
            #expect(!sut.isWaitingForTurn)
        }

        @Test("The turn a view controller is dismissed in doesn't decide on it, since its autorelease pool hasn't drained")
        func notDueInItsOwnTurn() {
            let screen = TrackedClass(name: "ProfileViewController", qualifiedName: "Example.ProfileViewController")
            var sut = LeakTracker()

            sut.dismiss(7, of: screen)
            let actual = sut.dueForCheck

            #expect(actual.isEmpty)
            #expect(sut.isWaitingForTurn)
        }

        @Test("A view controller that deallocates before its turn ends is never flagged")
        func deallocatedInTime() {
            let screen = TrackedClass(name: "ProfileViewController", qualifiedName: "Example.ProfileViewController")
            var sut = LeakTracker()

            sut.dismiss(7, of: screen)
            _ = sut.endTurn(at: Date(timeIntervalSince1970: 1), detached: [])
            sut.end(7)
            let actual = sut.endTurn(at: Date(timeIntervalSince1970: 2), detached: [])

            #expect(actual.isEmpty)
            #expect(sut.suspects.isEmpty)
            #expect(sut.dismissedIDs.isEmpty)
        }

        @Test("A view controller shown again by the end of its turn is forgotten, not flagged")
        func shownAgain() {
            let screen = TrackedClass(name: "ProfileViewController", qualifiedName: "Example.ProfileViewController")
            var sut = LeakTracker()

            sut.dismiss(7, of: screen)
            _ = sut.endTurn(at: Date(timeIntervalSince1970: 1), detached: [])
            let actual = sut.endTurn(at: Date(timeIntervalSince1970: 2), detached: [])

            #expect(actual.isEmpty)
            #expect(sut.suspects.isEmpty)
            #expect(sut.dismissedIDs.isEmpty)
        }

        @Test("A flagged view controller that deallocates later stops being a suspect")
        func releasedLate() {
            let screen = TrackedClass(name: "ProfileViewController", qualifiedName: "Example.ProfileViewController")
            var sut = LeakTracker()
            sut.dismiss(7, of: screen)
            _ = sut.endTurn(at: Date(timeIntervalSince1970: 1), detached: [7])
            _ = sut.endTurn(at: Date(timeIntervalSince1970: 2), detached: [7])

            sut.end(7)

            #expect(sut.suspects.isEmpty)
            #expect(sut.dueForCheck.isEmpty)
        }

        @Test("A flagged view controller back on screen stops being a suspect at the end of a turn")
        func flaggedShownAgain() {
            let screen = TrackedClass(name: "ProfileViewController", qualifiedName: "Example.ProfileViewController")
            var sut = LeakTracker()
            sut.dismiss(7, of: screen)
            _ = sut.endTurn(at: Date(timeIntervalSince1970: 1), detached: [7])
            _ = sut.endTurn(at: Date(timeIntervalSince1970: 2), detached: [7])

            let actual = sut.endTurn(at: Date(timeIntervalSince1970: 3), detached: [])

            #expect(actual.isEmpty)
            #expect(sut.suspects.isEmpty)
        }

        @Test("A flagged view controller still off screen stays flagged, with its first date, and isn't flagged again")
        func staysFlagged() {
            let screen = TrackedClass(name: "ProfileViewController", qualifiedName: "Example.ProfileViewController")
            let flaggedAt = Date(timeIntervalSince1970: 2)
            let expected = [LeakSuspect(type: screen, reason: .aliveAfterDismissal, count: 1, since: flaggedAt)]
            var sut = LeakTracker()
            sut.dismiss(7, of: screen)
            _ = sut.endTurn(at: Date(timeIntervalSince1970: 1), detached: [7])
            _ = sut.endTurn(at: flaggedAt, detached: [7])

            sut.dismiss(7, of: screen)
            let actual = sut.endTurn(at: Date(timeIntervalSince1970: 3), detached: [7])

            #expect(actual.isEmpty)
            #expect(sut.suspects == expected)
        }

        @Test("Two flagged view controllers of one class are one suspect with a count of two, flagged at the earlier date")
        func groupedByClass() {
            let screen = TrackedClass(name: "ProfileViewController", qualifiedName: "Example.ProfileViewController")
            let first = Date(timeIntervalSince1970: 2)
            let expected = [LeakSuspect(type: screen, reason: .aliveAfterDismissal, count: 2, since: first)]
            var sut = LeakTracker()
            sut.dismiss(7, of: screen)
            _ = sut.endTurn(at: Date(timeIntervalSince1970: 1), detached: [7])
            _ = sut.endTurn(at: first, detached: [7])

            sut.dismiss(8, of: screen)
            _ = sut.endTurn(at: Date(timeIntervalSince1970: 3), detached: [7, 8])
            let actual = sut.endTurn(at: Date(timeIntervalSince1970: 4), detached: [7, 8])

            #expect(actual == expected)
            #expect(sut.suspects == expected)
        }

        @Test("Two classes of one name in different modules are separate suspects")
        func sameNameDifferentModules() {
            let example = TrackedClass(name: "SettingsViewController", qualifiedName: "Example.SettingsViewController")
            let settings = TrackedClass(name: "SettingsViewController", qualifiedName: "Settings.SettingsViewController")
            var sut = LeakTracker()
            sut.dismiss(1, of: example)
            sut.dismiss(2, of: settings)
            _ = sut.endTurn(at: Date(timeIntervalSince1970: 1), detached: [])

            let actual = sut.endTurn(at: Date(timeIntervalSince1970: 2), detached: [1, 2])

            #expect(actual.map(\.type.qualifiedName) == ["Example.SettingsViewController", "Settings.SettingsViewController"])
            #expect(actual.map(\.count) == [1, 1])
        }

        @Test("Suspects list the most recently flagged first")
        func newestFirst() {
            let older = TrackedClass(name: "ProfileViewController", qualifiedName: "Example.ProfileViewController")
            let newer = TrackedClass(name: "SettingsViewController", qualifiedName: "Example.SettingsViewController")
            var sut = LeakTracker()
            sut.dismiss(1, of: older)
            _ = sut.endTurn(at: Date(timeIntervalSince1970: 1), detached: [])
            _ = sut.endTurn(at: Date(timeIntervalSince1970: 2), detached: [1])
            sut.dismiss(2, of: newer)
            _ = sut.endTurn(at: Date(timeIntervalSince1970: 3), detached: [1])
            _ = sut.endTurn(at: Date(timeIntervalSince1970: 4), detached: [1, 2])

            let actual = sut.suspects.map(\.type.name)

            #expect(actual == ["SettingsViewController", "ProfileViewController"])
        }

        @Test("Tracked objects up to the limit are no suspect")
        func atLimit() {
            let model = TrackedClass(name: "ProfileModel", qualifiedName: "Example.ProfileModel")
            var sut = LeakTracker()

            let first = sut.track(1, of: model, maxCount: 2, at: Date(timeIntervalSince1970: 1))
            let second = sut.track(2, of: model, maxCount: 2, at: Date(timeIntervalSince1970: 2))

            #expect(first.isEmpty)
            #expect(second.isEmpty)
            #expect(sut.suspects.isEmpty)
        }

        @Test("One object over the limit makes its class a suspect, with the count, the limit and when it went over")
        func overLimit() {
            let model = TrackedClass(name: "ProfileModel", qualifiedName: "Example.ProfileModel")
            let wentOver = Date(timeIntervalSince1970: 2)
            let expected = [LeakSuspect(type: model, reason: .overLimit(maxCount: 1), count: 2, since: wentOver)]
            var sut = LeakTracker()
            _ = sut.track(1, of: model, maxCount: 1, at: Date(timeIntervalSince1970: 1))

            let actual = sut.track(2, of: model, maxCount: 1, at: wentOver)

            #expect(actual == expected)
            #expect(sut.suspects == expected)
        }

        @Test("Each further object over the limit flags the class again with the new count, still since it went over")
        func furtherOverLimit() {
            let model = TrackedClass(name: "ProfileModel", qualifiedName: "Example.ProfileModel")
            let wentOver = Date(timeIntervalSince1970: 2)
            let expected = [LeakSuspect(type: model, reason: .overLimit(maxCount: 1), count: 3, since: wentOver)]
            var sut = LeakTracker()
            _ = sut.track(1, of: model, maxCount: 1, at: Date(timeIntervalSince1970: 1))
            _ = sut.track(2, of: model, maxCount: 1, at: wentOver)

            let actual = sut.track(3, of: model, maxCount: 1, at: Date(timeIntervalSince1970: 3))

            #expect(actual == expected)
        }

        @Test("Once enough objects deallocate to reach the limit again, the class is no suspect")
        func backToLimit() {
            let model = TrackedClass(name: "ProfileModel", qualifiedName: "Example.ProfileModel")
            var sut = LeakTracker()
            _ = sut.track(1, of: model, maxCount: 1, at: Date(timeIntervalSince1970: 1))
            _ = sut.track(2, of: model, maxCount: 1, at: Date(timeIntervalSince1970: 2))
            _ = sut.track(3, of: model, maxCount: 1, at: Date(timeIntervalSince1970: 3))

            sut.end(1)
            let stillOver = sut.suspects.map(\.count)
            sut.end(3)

            #expect(stillOver == [2])
            #expect(sut.suspects.isEmpty)
        }

        @Test("Going over the limit again after coming back under it is flagged from the new date")
        func overAgain() {
            let model = TrackedClass(name: "ProfileModel", qualifiedName: "Example.ProfileModel")
            let again = Date(timeIntervalSince1970: 4)
            var sut = LeakTracker()
            _ = sut.track(1, of: model, maxCount: 1, at: Date(timeIntervalSince1970: 1))
            _ = sut.track(2, of: model, maxCount: 1, at: Date(timeIntervalSince1970: 2))
            sut.end(2)

            let actual = sut.track(3, of: model, maxCount: 1, at: again)

            #expect(actual.map(\.since) == [again])
        }

        @Test("An object tracked twice is counted once")
        func trackedTwice() {
            let model = TrackedClass(name: "ProfileModel", qualifiedName: "Example.ProfileModel")
            var sut = LeakTracker()
            _ = sut.track(1, of: model, maxCount: 1, at: Date(timeIntervalSince1970: 1))

            let actual = sut.track(1, of: model, maxCount: 1, at: Date(timeIntervalSince1970: 2))

            #expect(actual.isEmpty)
            #expect(sut.suspects.isEmpty)
        }

        @Test("The last limit given for a class is the one used")
        func lastLimitWins() {
            let model = TrackedClass(name: "ProfileModel", qualifiedName: "Example.ProfileModel")
            var sut = LeakTracker()
            _ = sut.track(1, of: model, maxCount: 1, at: Date(timeIntervalSince1970: 1))

            let actual = sut.track(2, of: model, maxCount: 2, at: Date(timeIntervalSince1970: 2))

            #expect(actual.isEmpty)
            #expect(sut.suspects.isEmpty)
        }

        @Test("The end of an instance the tracker never knew changes nothing")
        func unknownEnd() {
            let model = TrackedClass(name: "ProfileModel", qualifiedName: "Example.ProfileModel")
            var sut = LeakTracker()
            _ = sut.track(1, of: model, maxCount: 1, at: Date(timeIntervalSince1970: 1))
            let expected = sut

            sut.end(99)

            #expect(sut == expected)
        }

        @Test("A view controller over its own limit and alive after dismissal is two suspects")
        func bothReasons() {
            let screen = TrackedClass(name: "ProfileViewController", qualifiedName: "Example.ProfileViewController")
            var sut = LeakTracker()
            _ = sut.track(1, of: screen, maxCount: 1, at: Date(timeIntervalSince1970: 1))
            _ = sut.track(2, of: screen, maxCount: 1, at: Date(timeIntervalSince1970: 1))
            sut.dismiss(1, of: screen)
            _ = sut.endTurn(at: Date(timeIntervalSince1970: 2), detached: [])
            _ = sut.endTurn(at: Date(timeIntervalSince1970: 3), detached: [1])

            let actual = sut.suspects.map(\.reason)

            #expect(actual == [.aliveAfterDismissal, .overLimit(maxCount: 1)])
        }
    }
#endif
