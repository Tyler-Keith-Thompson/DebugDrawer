// ViewInspector is linked on Apple platforms only, and the views are tested on the Mac.
#if os(macOS)
    @testable import DebugDrawerFeatureFlagsPlugin
    import SwiftUI
    import Testing
    import ViewInspector

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct FeatureFlagsViewTests {
        @Test("Flipping a Boolean flag's switch overrides it, stored and applied")
        func toggleOverrides() throws {
            let storage = FakeFeatureFlagOverrideStorage()
            let provider = FakeFeatureFlagProvider([FeatureFlag(key: "newCheckout", liveValue: .bool(false), title: "New checkout")])
            let sut = FeatureFlagsPluginView(store: FeatureFlagStore(provider: provider, storage: storage))

            try sut.inspect().find(ViewType.Toggle.self, where: { try $0.labelView().text().string() == "New checkout" }).tap()

            #expect(storage.values == ["newCheckout": .bool(true)])
            #expect(provider.calls == [.set("newCheckout", .bool(true))])
        }

        @Test("Typing in a string flag's field overrides it, empty text included")
        func textOverrides() throws {
            let storage = FakeFeatureFlagOverrideStorage()
            let provider = FakeFeatureFlagProvider([FeatureFlag(key: "theme", liveValue: .string("light"), title: "Theme")])
            let sut = FeatureFlagsPluginView(store: FeatureFlagStore(provider: provider, storage: storage))

            try sut.inspect().find(ViewType.TextField.self, where: { try $0.accessibilityLabel().string() == "Theme" }).setInput("")

            #expect(storage.values == ["theme": .string("")])
        }

        @Test("A number flag's field shows the value the app reads")
        func numberField() throws {
            let provider = FakeFeatureFlagProvider([FeatureFlag(key: "discount", liveValue: .number(0.1), title: "Discount")])
            provider.applied = ["discount": .number(0.25)]
            let sut = FeatureFlagsPluginView(store: FeatureFlagStore(provider: provider, storage: FakeFeatureFlagOverrideStorage()))

            let field = try sut.inspect().find(ViewType.TextField.self, where: { try $0.accessibilityLabel().string() == "Discount" })

            #expect(try field.labelView().text().string() == "Discount")
            #expect(try sut.inspect().find(text: "Live: 0.1").string() == "Live: 0.1")
        }

        @Test("Entering a number in a number flag's field overrides it")
        func numberOverrides() throws {
            let storage = FakeFeatureFlagOverrideStorage()
            let provider = FakeFeatureFlagProvider([FeatureFlag(key: "discount", liveValue: .number(0.1), title: "Discount")])
            let sut = FeatureFlagsPluginView(store: FeatureFlagStore(provider: provider, storage: storage))

            try sut.inspect().find(ViewType.TextField.self, where: { try $0.accessibilityLabel().string() == "Discount" }).setInput("0.5")

            #expect(storage.values == ["discount": .number(0.5)])
        }

        @Test("Text that isn't a number overrides nothing")
        func numberRejectsText() throws {
            let storage = FakeFeatureFlagOverrideStorage()
            let provider = FakeFeatureFlagProvider([FeatureFlag(key: "discount", liveValue: .number(0.1), title: "Discount")])
            let sut = FeatureFlagsPluginView(store: FeatureFlagStore(provider: provider, storage: storage))

            try sut.inspect().find(ViewType.TextField.self, where: { try $0.accessibilityLabel().string() == "Discount" }).setInput("lots")

            #expect(storage.values.isEmpty)
        }

        @Test("An overridden flag says so and has a button that clears its override")
        func clearOne() throws {
            let storage = FakeFeatureFlagOverrideStorage(["newCheckout": .bool(true), "theme": .string("dark")])
            let provider = FakeFeatureFlagProvider([
                FeatureFlag(key: "newCheckout", liveValue: .bool(false), title: "New checkout"),
                FeatureFlag(key: "theme", liveValue: .string("light"), title: "Theme")
            ])
            let sut = FeatureFlagsPluginView(store: FeatureFlagStore(provider: provider, storage: storage))
            provider.calls = []
            let inspected = try sut.inspect()
            let tags = inspected.findAll(ViewType.Text.self, where: { try $0.string() == "Overridden" })

            try inspected.find(ViewType.Button.self, where: { try $0.accessibilityLabel().string() == "Clear override of New checkout" }).tap()

            #expect(tags.count == 2)
            #expect(storage.values == ["theme": .string("dark")])
            #expect(provider.calls == [.clear("newCheckout")])
        }

        @Test("A flag without an override has no clear button and no Overridden tag")
        func notOverridden() throws {
            let provider = FakeFeatureFlagProvider([FeatureFlag(key: "newCheckout", liveValue: .bool(false), title: "New checkout")])
            let sut = FeatureFlagsPluginView(store: FeatureFlagStore(provider: provider, storage: FakeFeatureFlagOverrideStorage()))
            let inspected = try sut.inspect()

            let clearButtons = inspected
                .findAll(ViewType.Button.self, where: { try $0.accessibilityLabel().string() == "Clear override of New checkout" })
            let tags = inspected.findAll(ViewType.Text.self, where: { try $0.string() == "Overridden" })

            #expect(clearButtons.isEmpty)
            #expect(tags.isEmpty)
        }

        @Test("Reset All clears every override and leaves the defaults' other keys alone")
        func resetAll() throws {
            let storage = FakeFeatureFlagOverrideStorage(["newCheckout": .bool(true), "gone": .number(1)])
            let provider = FakeFeatureFlagProvider([FeatureFlag(key: "newCheckout", liveValue: .bool(false))])
            let sut = FeatureFlagsPluginView(store: FeatureFlagStore(provider: provider, storage: storage))

            try sut.inspect().find(button: "Reset All").tap()

            #expect(storage.values.isEmpty)
            #expect(provider.applied.isEmpty)
        }

        @Test("Reset All is disabled while no flag is overridden")
        func resetAllDisabled() throws {
            let provider = FakeFeatureFlagProvider([FeatureFlag(key: "newCheckout", liveValue: .bool(false))])
            let sut = FeatureFlagsPluginView(store: FeatureFlagStore(provider: provider, storage: FakeFeatureFlagOverrideStorage()))

            let actual = try sut.inspect().find(button: "Reset All").isDisabled()

            #expect(actual)
        }

        @Test("The overridden-only switch drives the filter binding")
        func overriddenOnlySwitch() throws {
            var isOverriddenOnly = false
            let sut = FeatureFlagsView(
                rows: [FeatureFlagRowState(FeatureFlag(key: "a", liveValue: .bool(false)), currentValue: nil, override: nil)],
                overrideCount: 0,
                query: .constant(""),
                isOverriddenOnly: Binding(get: { isOverriddenOnly }, set: { isOverriddenOnly = $0 }),
                onOverride: { _, _ in },
                onClear: { _ in },
                onClearAll: {},
                onRefresh: {}
            )

            try sut.inspect().find(ViewType.Toggle.self, where: { try $0.labelView().text().string() == "Overridden only" }).tap()

            #expect(isOverriddenOnly)
        }

        @Test("Typing in the filter field drives the search binding")
        func searchField() throws {
            var query = ""
            let sut = FeatureFlagsView(
                rows: [FeatureFlagRowState(FeatureFlag(key: "a", liveValue: .bool(false)), currentValue: nil, override: nil)],
                overrideCount: 0,
                query: Binding(get: { query }, set: { query = $0 }),
                isOverriddenOnly: .constant(false),
                onOverride: { _, _ in },
                onClear: { _ in },
                onClearAll: {},
                onRefresh: {}
            )

            try sut.inspect()
                .find(ViewType.TextField.self, where: { try $0.accessibilityLabel().string() == "Filter flags by key or title" }).setInput("check")

            #expect(query == "check")
        }

        @Test("Only overridden flags are listed while the filter is on")
        func overriddenOnlyFilters() throws {
            let rows = [
                FeatureFlagRowState(FeatureFlag(key: "newCheckout", liveValue: .bool(false)), currentValue: .bool(true), override: .bool(true)),
                FeatureFlagRowState(FeatureFlag(key: "legacyCheckout", liveValue: .bool(true)), currentValue: nil, override: nil)
            ]
            let sut = FeatureFlagsView(
                rows: rows, overrideCount: 1, query: .constant(""), isOverriddenOnly: .constant(true),
                onOverride: { _, _ in }, onClear: { _ in }, onClearAll: {}, onRefresh: {}
            )

            let actual = try sut.inspect().findAll(FeatureFlagRow.self).map { try $0.actualView().row.id }

            #expect(actual == ["newCheckout"])
        }

        @Test("With the filter on and nothing overridden, the plugin says no flag is overridden and keeps the search field")
        func overriddenOnlyEmpty() throws {
            let rows = [FeatureFlagRowState(FeatureFlag(key: "a", liveValue: .bool(false)), currentValue: nil, override: nil)]
            let sut = FeatureFlagsView(
                rows: rows, overrideCount: 0, query: .constant(""), isOverriddenOnly: .constant(true),
                onOverride: { _, _ in }, onClear: { _ in }, onClearAll: {}, onRefresh: {}
            )
            let inspected = try sut.inspect()

            #expect(try inspected.find(text: "No flag is overridden").string() == "No flag is overridden")
            #expect(throws: Never.self) {
                try inspected.find(ViewType.TextField.self, where: { try $0.accessibilityLabel().string() == "Filter flags by key or title" })
            }
        }

        @Test("A search that matches nothing says so")
        func noMatches() throws {
            let rows = [FeatureFlagRowState(FeatureFlag(key: "a", liveValue: .bool(false)), currentValue: nil, override: nil)]
            let sut = FeatureFlagsView(
                rows: rows, overrideCount: 0, query: .constant("zzz"), isOverriddenOnly: .constant(false),
                onOverride: { _, _ in }, onClear: { _ in }, onClearAll: {}, onRefresh: {}
            )

            let actual = try sut.inspect().find(text: "No flag matches")

            #expect(try actual.string() == "No flag matches")
        }

        @Test("With no flags, the plugin says the provider lists none")
        func empty() throws {
            let sut = FeatureFlagsPluginView(store: FeatureFlagStore(provider: FakeFeatureFlagProvider(), storage: FakeFeatureFlagOverrideStorage()))

            let actual = try sut.inspect().find(text: "The provider lists no flags")

            #expect(try actual.string() == "The provider lists no flags")
        }

        @Test("Refresh tells the drawer to read the provider again")
        func refresh() throws {
            let provider = FakeFeatureFlagProvider([FeatureFlag(key: "a", liveValue: .bool(true))])
            let store = FeatureFlagStore(provider: provider, storage: FakeFeatureFlagOverrideStorage())
            let sut = FeatureFlagsPluginView(store: store)
            var actual = 0
            let subscription = store.objectWillChange.sink { actual += 1 }
            defer { subscription.cancel() }

            try sut.inspect().find(button: "Refresh").tap()

            #expect(actual == 1)
        }
    }
#endif
