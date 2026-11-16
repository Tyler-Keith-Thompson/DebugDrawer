#if DEBUG
    @testable import DebugDrawerLeakDetectorPlugin
    import Foundation
    import Testing

    @MainActor
    @Suite
    struct LeakStoreTests {
        @Test("A new store has no suspects and ignores nothing")
        func empty() {
            let sut = LeakStore()

            #expect(sut.suspects.isEmpty)
            #expect(sut.visibleSuspects.isEmpty)
            #expect(sut.ignoredSuspectCount == 0)
        }

        @Test("An update shows the suspects and reports how many there are")
        func update() {
            var counts: [Int] = []
            let sut = LeakStore { counts.append($0) }
            let suspects = [
                LeakSuspect(
                    type: TrackedClass(name: "ProfileViewController", qualifiedName: "Example.ProfileViewController"),
                    reason: .aliveAfterDismissal, count: 2, since: Date(timeIntervalSince1970: 2)
                ),
                LeakSuspect(
                    type: TrackedClass(name: "ProfileModel", qualifiedName: "Example.ProfileModel"),
                    reason: .overLimit(maxCount: 1), count: 3, since: Date(timeIntervalSince1970: 1)
                )
            ]

            sut.update(suspects)

            #expect(sut.visibleSuspects == suspects)
            #expect(counts == [2])
        }

        @Test("Ignoring a class hides its suspects, counts them as ignored and lowers the reported count")
        func ignore() {
            var counts: [Int] = []
            let sut = LeakStore { counts.append($0) }
            let screen = LeakSuspect(
                type: TrackedClass(name: "ProfileViewController", qualifiedName: "Example.ProfileViewController"),
                reason: .aliveAfterDismissal, count: 2, since: Date(timeIntervalSince1970: 2)
            )
            let model = LeakSuspect(
                type: TrackedClass(name: "ProfileModel", qualifiedName: "Example.ProfileModel"),
                reason: .overLimit(maxCount: 1), count: 3, since: Date(timeIntervalSince1970: 1)
            )
            sut.update([screen, model])

            sut.ignore(screen)

            #expect(sut.visibleSuspects == [model])
            #expect(sut.ignoredSuspectCount == 1)
            #expect(sut.isIgnored(screen))
            #expect(counts == [2, 1])
        }

        @Test("An ignored class stays ignored when it is flagged again")
        func ignoredStaysIgnored() {
            let sut = LeakStore()
            let screen = LeakSuspect(
                type: TrackedClass(name: "ProfileViewController", qualifiedName: "Example.ProfileViewController"),
                reason: .aliveAfterDismissal, count: 1, since: Date(timeIntervalSince1970: 2)
            )
            sut.update([screen])
            sut.ignore(screen)

            sut.update([LeakSuspect(type: screen.type, reason: .aliveAfterDismissal, count: 2, since: screen.since)])

            #expect(sut.visibleSuspects.isEmpty)
            #expect(sut.ignoredSuspectCount == 1)
        }

        @Test("Ignoring the class covers both of its suspects, alive after dismissal and over its limit")
        func ignoreCoversBothReasons() {
            let type = TrackedClass(name: "ProfileViewController", qualifiedName: "Example.ProfileViewController")
            let dismissed = LeakSuspect(type: type, reason: .aliveAfterDismissal, count: 1, since: Date(timeIntervalSince1970: 2))
            let sut = LeakStore()
            sut.update([dismissed, LeakSuspect(type: type, reason: .overLimit(maxCount: 1), count: 2, since: Date(timeIntervalSince1970: 1))])

            sut.ignore(dismissed)

            #expect(sut.visibleSuspects.isEmpty)
            #expect(sut.ignoredSuspectCount == 2)
        }

        @Test("Stop Ignoring shows every ignored class's suspects again")
        func stopIgnoring() {
            var counts: [Int] = []
            let sut = LeakStore { counts.append($0) }
            let screen = LeakSuspect(
                type: TrackedClass(name: "ProfileViewController", qualifiedName: "Example.ProfileViewController"),
                reason: .aliveAfterDismissal, count: 1, since: Date(timeIntervalSince1970: 2)
            )
            sut.update([screen])
            sut.ignore(screen)

            sut.stopIgnoring()

            #expect(sut.visibleSuspects == [screen])
            #expect(sut.ignoredSuspectCount == 0)
            #expect(counts == [1, 0, 1])
        }
    }
#endif
