// ViewInspector is linked on Apple platforms only, and the views are tested on the Mac.
#if os(macOS)
    @testable import DebugDrawerLeakDetectorPlugin
    import Foundation
    import SwiftUI
    import Testing
    import ViewInspector

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct LeaksViewTests {
        @Test("With no suspects the plugin says what would appear, and offers no buttons")
        func empty() throws {
            let sut = LeaksView(suspects: [], ignoredCount: 0, onIgnore: { _ in }, onStopIgnoring: {})
            let expected = LeaksView.emptyText

            let actual = try sut.inspect().find(text: expected).string()

            #expect(actual == expected)
            #expect(throws: (any Error).self) { try sut.inspect().find(ViewType.Button.self) }
        }

        @Test("Each suspect shows its class, what is wrong and what kind of object it is")
        func rows() throws {
            let suspects = [
                LeakSuspect(
                    type: TrackedClass(name: "ProfileViewController", qualifiedName: "Example.ProfileViewController"),
                    reason: .aliveAfterDismissal, count: 2, since: Date(timeIntervalSince1970: 1_763_290_000)
                ),
                LeakSuspect(
                    type: TrackedClass(name: "ProfileModel", qualifiedName: "Example.ProfileModel"),
                    reason: .overLimit(maxCount: 1), count: 3, since: Date(timeIntervalSince1970: 1_763_289_000)
                )
            ]
            let sut = LeaksView(suspects: suspects, ignoredCount: 0, onIgnore: { _ in }, onStopIgnoring: {})
                .environment(\.locale, Locale(identifier: "en_US"))
                .environment(\.timeZone, try #require(TimeZone(identifier: "UTC")))
            // en_US puts a narrow no-break space before AM.
            let expected = [
                "ProfileViewController", "2 still alive after dismissal", "View controller · flagged Nov 16, 2025 at 10:46:40\u{202F}AM",
                "ProfileModel", "3 alive, at most 1 expected", "Tracked object · flagged Nov 16, 2025 at 10:30:00\u{202F}AM"
            ]

            let actual = try sut.inspect().findAll(ViewType.Text.self).map { try $0.string() }.filter { $0 != "Ignore" }

            #expect(actual == expected)
        }

        @Test("Ignore on a row ignores that suspect")
        func ignore() throws {
            let screen = LeakSuspect(
                type: TrackedClass(name: "ProfileViewController", qualifiedName: "Example.ProfileViewController"),
                reason: .aliveAfterDismissal, count: 1, since: Date(timeIntervalSince1970: 2)
            )
            let model = LeakSuspect(
                type: TrackedClass(name: "ProfileModel", qualifiedName: "Example.ProfileModel"),
                reason: .overLimit(maxCount: 1), count: 2, since: Date(timeIntervalSince1970: 1)
            )
            var ignored: [LeakSuspect] = []
            let sut = LeaksView(suspects: [screen, model], ignoredCount: 0, onIgnore: { ignored.append($0) }, onStopIgnoring: {})

            try sut.inspect().findAll(ViewType.Button.self)[1].tap()

            #expect(ignored == [model])
        }

        @Test("Each Ignore button names its class for VoiceOver")
        func ignoreLabels() throws {
            let screen = LeakSuspect(
                type: TrackedClass(name: "ProfileViewController", qualifiedName: "Example.ProfileViewController"),
                reason: .aliveAfterDismissal, count: 1, since: Date(timeIntervalSince1970: 2)
            )
            let sut = LeaksView(suspects: [screen], ignoredCount: 0, onIgnore: { _ in }, onStopIgnoring: {})

            let actual = try sut.inspect().find(ViewType.Button.self).accessibilityLabel().string()

            #expect(actual == "Ignore ProfileViewController")
        }

        @Test("With ignored suspects the plugin says how many, and Stop Ignoring shows them again")
        func stopIgnoring() throws {
            var stopped = 0
            let sut = LeaksView(suspects: [], ignoredCount: 2, onIgnore: { _ in }, onStopIgnoring: { stopped += 1 })

            try sut.inspect().find(button: "Stop Ignoring").tap()

            #expect(try sut.inspect().find(text: "2 suspects ignored").string() == "2 suspects ignored")
            #expect(stopped == 1)
        }

        @Test("One ignored suspect is named in the singular")
        func oneIgnored() throws {
            let sut = LeaksView(suspects: [], ignoredCount: 1, onIgnore: { _ in }, onStopIgnoring: {})

            let actual = try sut.inspect().find(text: "1 suspect ignored").string()

            #expect(actual == "1 suspect ignored")
        }

        @Test("The plugin's view shows the store's suspects not ignored, and the ignored count")
        func pluginView() throws {
            let store = LeakStore()
            let screen = LeakSuspect(
                type: TrackedClass(name: "ProfileViewController", qualifiedName: "Example.ProfileViewController"),
                reason: .aliveAfterDismissal, count: 1, since: Date(timeIntervalSince1970: 2)
            )
            let model = LeakSuspect(
                type: TrackedClass(name: "ProfileModel", qualifiedName: "Example.ProfileModel"),
                reason: .overLimit(maxCount: 1), count: 2, since: Date(timeIntervalSince1970: 1)
            )
            store.update([screen, model])
            store.ignore(screen)
            let sut = LeakDetectorPluginView(store: store)

            let actual = try sut.inspect().find(LeaksView.self).actualView()

            #expect(actual.suspects == [model])
            #expect(actual.ignoredCount == 1)
        }
    }
#endif
