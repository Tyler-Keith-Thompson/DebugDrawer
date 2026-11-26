@testable import DebugDrawerReceiver
import Foundation
import Testing

// The scenario launcher's model and declarations on their own: what each parameter kind takes, at
// the boundaries of its bounds, and what a handler receives.
@MainActor
@Suite
struct ScenariosTests {
    @Test("A string parameter takes text up to its maximum length, empty included, and nothing of another kind")
    func stringParameterBounds() {
        let sut = DebugDrawerScenarioParameter.string("promo", maximumLength: 3)

        #expect(sut.accepts(.string("")))
        #expect(sut.accepts(.string("abc")))
        #expect(!sut.accepts(.string("abcd")))
        #expect(!sut.accepts(.integer(1)))
        #expect(!sut.accepts(.boolean(true)))
    }

    @Test("An integer parameter takes a number at either end of its range and none outside it")
    func integerParameterBounds() {
        let sut = DebugDrawerScenarioParameter.integer("step", default: 1, in: 1 ... 5)

        #expect(sut.accepts(.integer(1)))
        #expect(sut.accepts(.integer(5)))
        #expect(!sut.accepts(.integer(0)))
        #expect(!sut.accepts(.integer(6)))
        #expect(!sut.accepts(.string("3")))
    }

    @Test("A boolean parameter takes either switch value and no other kind")
    func booleanParameterKind() {
        let sut = DebugDrawerScenarioParameter.boolean("trial")

        #expect(sut.accepts(.boolean(true)))
        #expect(sut.accepts(.boolean(false)))
        #expect(!sut.accepts(.integer(1)))
        #expect(!sut.accepts(.string("true")))
    }

    @Test("A choice parameter takes one of its options only, as text; its default is the first option unless given")
    func choiceParameterOptions() {
        let sut = DebugDrawerScenarioParameter.choice("plan", options: ["monthly", "annual"])
        let expectedDefault = DebugDrawerScenarioValue.string("monthly")

        let given = DebugDrawerScenarioParameter.choice("plan", options: ["monthly", "annual"], default: "annual")

        #expect(sut.defaultValue == expectedDefault)
        #expect(given.defaultValue == .string("annual"))
        #expect(sut.accepts(.string("annual")))
        #expect(!sut.accepts(.string("Annual")))
        #expect(!sut.accepts(.string("")))
        #expect(!sut.accepts(.integer(0)))
    }

    @Test("A parameter's title is its name unless given")
    func titleDefaultsToName() {
        let sut = DebugDrawerScenarioParameter.boolean("trial")

        #expect(sut.title == "trial")
        #expect(DebugDrawerScenarioParameter.boolean("trial", title: "Free Trial").title == "Free Trial")
    }

    @Test("The handler gets every declared parameter, typed, the default for one left out; accessors return nil for any other name or kind")
    func handlerArguments() throws {
        var received: [DebugDrawerScenario.Arguments] = []
        let scenario = DebugDrawerScenario("onboarding", title: "Onboarding", parameters: [
            .integer("step", default: 1, in: 1 ... 5),
            .string("name", default: "Jane"),
            .boolean("skipIntro")
        ]) { received.append($0) }
        let sut = try DebugDrawerScenarios(scenarios: [scenario], launchURL: nil, now: { Date(timeIntervalSinceReferenceDate: 0) })

        sut.perform(.run(scenario: "onboarding", arguments: ["step": .integer(3)]))

        let actual = try #require(received.first)
        #expect(received.count == 1)
        #expect(actual.integer("step") == 3)
        #expect(actual.string("name") == "Jane")
        #expect(actual.boolean("skipIntro") == false)
        #expect(actual.values.count == 3)
        #expect(actual.string("step") == nil)
        #expect(actual.integer("userID") == nil)
    }

    @Test("A scenario with no parameters runs with empty arguments, and any argument is refused malformedCommand")
    func scenarioWithoutParameters() throws {
        var runs = 0
        let scenario = DebugDrawerScenario("paywall", title: "Paywall") { _ in runs += 1 }
        let sut = try DebugDrawerScenarios(scenarios: [scenario], launchURL: nil, now: { Date(timeIntervalSinceReferenceDate: 0) })

        let refusals = [
            sut.refusal(of: .run(scenario: "paywall", arguments: [:])),
            sut.refusal(of: .run(scenario: "paywall", arguments: ["plan": .string("annual")]))
        ]
        sut.perform(.run(scenario: "paywall", arguments: [:]))

        #expect(refusals == [nil, .malformedCommand])
        #expect(runs == 1)
    }

    @Test("Performing a command the receiver would refuse runs no handler and records no launch")
    func performIgnoresRefusedCommands() throws {
        var runs = 0
        let scenario = DebugDrawerScenario("order", title: "Order", parameters: [.integer("id", default: 1, in: 1 ... 9)]) { _ in runs += 1 }
        let sut = try DebugDrawerScenarios(scenarios: [scenario], launchURL: nil, now: { Date(timeIntervalSinceReferenceDate: 0) })

        sut.perform(.run(scenario: "missing", arguments: [:]))
        sut.perform(.run(scenario: "order", arguments: ["id": .integer(10)]))

        #expect(runs == 0)
        #expect(sut.snapshot.lastRun == nil)
    }

    @Test("Each launch is numbered from 1 and dated by the model's clock")
    func launchesAreNumbered() throws {
        let date = Date(timeIntervalSinceReferenceDate: 1_000)
        let scenario = DebugDrawerScenario("home", title: "Home") { _ in }
        let sut = try DebugDrawerScenarios(scenarios: [scenario], launchURL: nil, now: { date })
        let expected = DebugDrawerScenarios.Run(number: 2, scenario: "home", date: date)

        sut.perform(.run(scenario: "home", arguments: [:]))
        sut.perform(.run(scenario: "home", arguments: [:]))

        #expect(sut.snapshot.lastRun == expected)
    }

    @Test("No scenarios is a valid, empty list")
    func emptyScenarios() throws {
        let sut = try DebugDrawerScenarios(scenarios: [])

        #expect(sut.snapshot.scenarios.isEmpty)
        #expect(sut.refusal(of: .run(scenario: "home", arguments: [:])) == .notExposed)
    }

    @Test("A command and a value survive JSON as a sidecar's transport carries them")
    func commandRoundTrips() throws {
        let command = DebugDrawerScenarios.Command.run(
            scenario: "open-order", arguments: ["id": .integer(.max), "note": .string("é"), "on": .boolean(true)]
        )
        let parameter = DebugDrawerScenarioParameter.integer("id", default: 0, in: Int.min ... Int.max)

        let actual = try JSONDecoder().decode(DebugDrawerScenarios.Command.self, from: JSONEncoder().encode(command))
        let decodedParameter = try JSONDecoder().decode(DebugDrawerScenarioParameter.self, from: JSONEncoder().encode(parameter))

        #expect(actual == command)
        #expect(decodedParameter == parameter)
    }
}
