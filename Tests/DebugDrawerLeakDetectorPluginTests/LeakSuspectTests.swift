#if DEBUG
    @testable import DebugDrawerLeakDetectorPlugin
    import Foundation
    import Testing

    @Suite
    struct LeakSuspectTests {
        @Test("A view controller suspect says how many are still alive after dismissal")
        func dismissedSummary() {
            let sut = LeakSuspect(
                type: TrackedClass(name: "ProfileViewController", qualifiedName: "Example.ProfileViewController"),
                reason: .aliveAfterDismissal, count: 2, since: Date(timeIntervalSince1970: 0)
            )

            let actual = sut.summary

            #expect(actual == "2 still alive after dismissal")
        }

        @Test("An over-limit suspect says how many are alive and how many are expected")
        func overLimitSummary() {
            let sut = LeakSuspect(
                type: TrackedClass(name: "ProfileModel", qualifiedName: "Example.ProfileModel"),
                reason: .overLimit(maxCount: 1), count: 3, since: Date(timeIntervalSince1970: 0)
            )

            let actual = sut.summary

            #expect(actual == "3 alive, at most 1 expected")
        }

        @Test("A view controller suspect's toast names the class still alive after it was dismissed")
        func dismissedToast() {
            let sut = LeakSuspect(
                type: TrackedClass(name: "ProfileViewController", qualifiedName: "Example.ProfileViewController"),
                reason: .aliveAfterDismissal, count: 1, since: Date(timeIntervalSince1970: 0)
            )

            let actual = sut.toastMessage

            #expect(actual == "ProfileViewController is still alive after it was dismissed")
        }

        @Test("An over-limit suspect's toast gives the count and the limit")
        func overLimitToast() {
            let sut = LeakSuspect(
                type: TrackedClass(name: "ProfileModel", qualifiedName: "Example.ProfileModel"),
                reason: .overLimit(maxCount: 1), count: 2, since: Date(timeIntervalSince1970: 0)
            )

            let actual = sut.toastMessage

            #expect(actual == "2 ProfileModel instances alive, at most 1 expected")
        }

        @Test("As text, a suspect is its class with the module, what is wrong, and when it was flagged")
        func text() {
            let sut = LeakSuspect(
                type: TrackedClass(name: "ProfileViewController", qualifiedName: "Example.ProfileViewController"),
                reason: .aliveAfterDismissal, count: 1, since: Date(timeIntervalSince1970: 1_763_290_000)
            )
            let expected = """
            Example.ProfileViewController
            1 still alive after dismissal
            Flagged: 2025-11-16T10:46:40Z

            """

            let actual = sut.text()

            #expect(actual == expected)
        }

        @Test("One class's two kinds of suspect have different identities")
        func identities() {
            let type = TrackedClass(name: "ProfileViewController", qualifiedName: "Example.ProfileViewController")
            let dismissed = LeakSuspect(type: type, reason: .aliveAfterDismissal, count: 1, since: Date(timeIntervalSince1970: 0))
            let overLimit = LeakSuspect(type: type, reason: .overLimit(maxCount: 1), count: 2, since: Date(timeIntervalSince1970: 0))

            let actual = [dismissed.id, overLimit.id]

            #expect(actual == ["dismissed:Example.ProfileViewController", "limit:Example.ProfileViewController"])
        }

        @Test("A tracked class is named as code writes it, and with its module")
        func trackedClassNames() {
            final class ProfileModel {}
            let model = ProfileModel()

            let actual = TrackedClass(of: model)

            #expect(actual.name == "ProfileModel")
            #expect(actual.qualifiedName.hasPrefix("DebugDrawerLeakDetectorPluginTests."))
            #expect(actual.qualifiedName.hasSuffix(".ProfileModel"))
        }
    }
#endif
