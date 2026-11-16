#if DEBUG
    @testable import DebugDrawerFeatureFlagsPlugin
    import Testing

    @Suite
    struct FeatureFlagRowStateTests {
        @Test("A row is titled by the flag's title, or its key without one")
        func title() {
            let titled = FeatureFlagRowState(
                FeatureFlag(key: "new-checkout", liveValue: .bool(false), title: "New checkout"),
                currentValue: nil,
                override: nil
            )
            let untitled = FeatureFlagRowState(FeatureFlag(key: "new-checkout", liveValue: .bool(false)), currentValue: nil, override: nil)

            #expect(titled.title == "New checkout")
            #expect(untitled.title == "new-checkout")
        }

        @Test("The control is chosen by the live value's kind and shows what the app reads", arguments: [
            (FeatureFlagValue.bool(false), FeatureFlagValue.bool(true), FeatureFlagRowState.Control.toggle(true)),
            (.number(1), .number(2.5), .number(2.5)),
            (.string("a"), .string("b"), .text("b"))
        ])
        func control(live: FeatureFlagValue, current: FeatureFlagValue, expected: FeatureFlagRowState.Control) {
            let actual = FeatureFlagRowState(FeatureFlag(key: "k", liveValue: live), currentValue: current, override: nil).control

            #expect(actual == expected)
        }

        @Test("With no current value from the provider, the control shows the override, then the live value")
        func fallback() {
            let flag = FeatureFlag(key: "k", liveValue: .number(1))

            let withOverride = FeatureFlagRowState(flag, currentValue: nil, override: .number(5)).control
            let withoutOverride = FeatureFlagRowState(flag, currentValue: nil, override: nil).control

            #expect(withOverride == .number(5))
            #expect(withoutOverride == .number(1))
        }

        @Test("An override of another kind than the live value stays shown as the override, and the control shows the live value")
        func otherKind() {
            let flag = FeatureFlag(key: "k", liveValue: .bool(false))

            let actual = FeatureFlagRowState(flag, currentValue: .string("on"), override: .string("on"))

            #expect(actual.control == .toggle(false))
            #expect(actual.override == .string("on"))
            #expect(actual.isOverridden)
        }

        @Test("Search matches the key, title or detail, ignoring case; an empty or blank search matches everything", arguments: [
            ("", true), ("   ", true), ("CHECKOUT", true), ("new-", true), ("payment", true), ("shipping", false)
        ])
        func matches(query: String, expected: Bool) {
            let row = FeatureFlagRowState(
                FeatureFlag(key: "new-checkout", liveValue: .bool(false), title: "New Checkout", detail: "The payment sheet"),
                currentValue: nil,
                override: nil
            )

            let actual = row.matches(query)

            #expect(actual == expected)
        }

        @Test("With no flags, the list is empty whatever the search and filter")
        func noFlags() {
            let actual = FeatureFlagList([], query: "x", overriddenOnly: true)

            #expect(actual == .noFlags)
        }

        @Test("Showing only overridden flags while none is overridden matches nothing")
        func overriddenOnlyNone() {
            let rows = [FeatureFlagRowState(FeatureFlag(key: "a", liveValue: .bool(false)), currentValue: nil, override: nil)]

            let actual = FeatureFlagList(rows, query: "", overriddenOnly: true)

            #expect(actual == .noMatches)
        }

        @Test("The filter and the search together keep only overridden flags that match")
        func filterAndSearch() {
            let rows = [
                FeatureFlagRowState(FeatureFlag(key: "checkout.new", liveValue: .bool(false)), currentValue: nil, override: .bool(true)),
                FeatureFlagRowState(FeatureFlag(key: "checkout.legacy", liveValue: .bool(true)), currentValue: nil, override: nil),
                FeatureFlagRowState(FeatureFlag(key: "theme", liveValue: .string("light")), currentValue: nil, override: .string("dark"))
            ]

            let actual = FeatureFlagList(rows, query: "checkout", overriddenOnly: true)

            #expect(actual == .flags([rows[0]]))
        }
    }
#endif
