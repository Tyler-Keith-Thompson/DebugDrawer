#if DEBUG
    import DebugDrawer
    @testable import DebugDrawerLeakDetectorPlugin
    import Foundation
    import Testing

    @MainActor
    @Suite
    struct LeakDetectorPluginTests {
        @Test("The plugin is Leaks, in the Performance category, and adds to bug reports")
        func identity() {
            let sut = LeakDetectorPlugin(store: LeakStore())

            #expect(sut.id == "LeakDetectorPlugin")
            #expect(sut.title == "Leaks")
            #expect(sut.category == "Performance")
            #expect(sut.icon == "memorychip")
            #expect(AnyDebugDrawerPlugin(sut).contributesToReport)
        }

        @Test("The drawer's search offers to stop ignoring suspects, found by \"retain cycle\" too")
        func action() throws {
            let store = LeakStore()
            let suspect = LeakSuspect(
                type: TrackedClass(name: "ProfileViewController", qualifiedName: "Example.ProfileViewController"),
                reason: .aliveAfterDismissal, count: 1, since: Date(timeIntervalSince1970: 1)
            )
            store.update([suspect])
            store.ignore(suspect)
            let sut = LeakDetectorPlugin(store: store)

            let actual = try #require(sut.actions.first)
            actual.perform()

            #expect(sut.actions.map(\.title) == ["Stop ignoring leak suspects"])
            #expect(actual.keywords.contains("retain cycle"))
            #expect(store.visibleSuspects == [suspect])
        }

        @Test("The bug report gets every suspect, in order, in leaks.txt")
        func report() throws {
            let suspects = [
                LeakSuspect(
                    type: TrackedClass(name: "ProfileViewController", qualifiedName: "Example.ProfileViewController"),
                    reason: .aliveAfterDismissal, count: 2, since: Date(timeIntervalSince1970: 1_763_290_000)
                ),
                LeakSuspect(
                    type: TrackedClass(name: "ProfileModel", qualifiedName: "Example.ProfileModel"),
                    reason: .overLimit(maxCount: 1), count: 3, since: Date(timeIntervalSince1970: 0)
                )
            ]
            let expected = """
            Example.ProfileViewController
            2 still alive after dismissal
            Flagged: 2025-11-16T10:46:40Z

            Example.ProfileModel
            3 alive, at most 1 expected
            Flagged: 1970-01-01T00:00:00Z

            """
            var actual = DebugDrawerReport()

            LeakDetectorPlugin.contribute(suspects, to: &actual)

            #expect(actual.files.map(\.name) == ["leaks.txt"])
            #expect(String(bytes: try #require(actual.files.first).data, encoding: .utf8) == expected)
        }

        @Test("No suspects add nothing to the bug report")
        func reportEmpty() {
            var actual = DebugDrawerReport()

            LeakDetectorPlugin.contribute([], to: &actual)

            #expect(actual.files.isEmpty)
        }

        @Test("The bug report leaves out ignored classes")
        func reportLeavesOutIgnored() {
            let store = LeakStore()
            let suspect = LeakSuspect(
                type: TrackedClass(name: "ProfileViewController", qualifiedName: "Example.ProfileViewController"),
                reason: .aliveAfterDismissal, count: 1, since: Date(timeIntervalSince1970: 1)
            )
            store.update([suspect])
            store.ignore(suspect)
            let sut = LeakDetectorPlugin(store: store)
            var actual = DebugDrawerReport()

            sut.contribute(to: &actual, redaction: .standard)

            #expect(actual.files.isEmpty)
        }
    }
#endif
