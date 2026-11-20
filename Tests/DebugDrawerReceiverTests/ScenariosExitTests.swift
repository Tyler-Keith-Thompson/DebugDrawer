// Exit tests sit apart from the other tests: builds for platforms that can't start a child process
// leave this file out.
#if os(macOS)
    import DebugDrawerReceiver
    import Testing

    @Suite
    struct ScenariosExitTests {
        @Test("A string parameter whose maximum length isn't positive, or whose default is longer, traps")
        func invalidStringParameterTraps() async {
            await #expect(processExitsWith: .failure) {
                _ = DebugDrawerScenarioParameter.string("promo", maximumLength: 0)
            }
            await #expect(processExitsWith: .failure) {
                _ = DebugDrawerScenarioParameter.string("promo", default: "TOOLONG", maximumLength: 3)
            }
        }

        @Test("An integer parameter whose default is outside its range traps")
        func integerDefaultOutsideRangeTraps() async {
            await #expect(processExitsWith: .failure) {
                _ = DebugDrawerScenarioParameter.integer("step", default: 0, in: 1 ... 5)
            }
        }

        @Test("A choice parameter with no options, a repeated option, or a default not among them traps")
        func invalidChoiceParameterTraps() async {
            await #expect(processExitsWith: .failure) {
                _ = DebugDrawerScenarioParameter.choice("plan", options: [])
            }
            await #expect(processExitsWith: .failure) {
                _ = DebugDrawerScenarioParameter.choice("plan", options: ["annual", "annual"])
            }
            await #expect(processExitsWith: .failure) {
                _ = DebugDrawerScenarioParameter.choice("plan", options: ["monthly", "annual"], default: "lifetime")
            }
        }

        @Test("A scenario with two parameters of one name traps")
        func repeatedParameterNameTraps() async {
            await #expect(processExitsWith: .failure) {
                _ = DebugDrawerScenario("order", title: "Order", parameters: [.boolean("id"), .integer("id")]) { _ in }
            }
        }

        @Test("Two scenarios with one ID trap")
        func repeatedScenarioIDTraps() async {
            await #expect(processExitsWith: .failure) {
                await MainActor.run {
                    _ = DebugDrawerScenarios(scenarios: [
                        DebugDrawerScenario("home", title: "Home") { _ in },
                        DebugDrawerScenario("home", title: "Home Again") { _ in }
                    ])
                }
            }
        }
    }
#endif
