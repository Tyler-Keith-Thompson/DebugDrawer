// What the scenarios refuse as they are made: scenarios sharing an ID, parameters sharing a name
// and parameter declarations that contradict themselves. Real in every build, so these run in
// debug and release alike.
import DebugDrawerReceiver
import Foundation
import Testing

@MainActor
@Suite
struct ScenariosValidationTests {
    @Test("A string parameter whose maximum length is 0 throws maximumLengthNotPositive")
    func zeroMaximumLength() {
        let expected = DebugDrawerScenarios.InvalidScenarios.maximumLengthNotPositive

        #expect(throws: expected) {
            _ = try DebugDrawerScenarios(scenarios: [
                DebugDrawerScenario("promo", title: "Promo", parameters: [.string("code", maximumLength: 0)]) { _ in }
            ])
        }
    }

    @Test("A string parameter whose default is longer than its maximum length throws defaultTooLong")
    func stringDefaultTooLong() {
        let expected = DebugDrawerScenarios.InvalidScenarios.defaultTooLong

        #expect(throws: expected) {
            _ = try DebugDrawerScenarios(scenarios: [
                DebugDrawerScenario("promo", title: "Promo", parameters: [.string("code", default: "TOOLONG", maximumLength: 3)]) { _ in }
            ])
        }
    }

    @Test("A string parameter whose default is exactly its maximum length is taken: the edge of the valid range")
    func stringDefaultAtMaximumLength() throws {
        let expected = DebugDrawerScenarioValue.string("ABC")

        let sut = try DebugDrawerScenarios(scenarios: [
            DebugDrawerScenario("promo", title: "Promo", parameters: [.string("code", default: "ABC", maximumLength: 3)]) { _ in }
        ])

        #expect(sut.snapshot.scenarios.first?.parameters.first?.defaultValue == expected)
    }

    @Test("An integer parameter whose default is below its range throws defaultOutOfRange")
    func integerDefaultBelowRange() {
        let expected = DebugDrawerScenarios.InvalidScenarios.defaultOutOfRange

        #expect(throws: expected) {
            _ = try DebugDrawerScenarios(scenarios: [
                DebugDrawerScenario("onboarding", title: "Onboarding", parameters: [.integer("step", default: 0, in: 1 ... 5)]) { _ in }
            ])
        }
    }

    @Test("An integer parameter whose default is above its range throws defaultOutOfRange")
    func integerDefaultAboveRange() {
        let expected = DebugDrawerScenarios.InvalidScenarios.defaultOutOfRange

        #expect(throws: expected) {
            _ = try DebugDrawerScenarios(scenarios: [
                DebugDrawerScenario("onboarding", title: "Onboarding", parameters: [.integer("step", default: 6, in: 1 ... 5)]) { _ in }
            ])
        }
    }

    @Test("Integer parameters whose defaults are their range's bounds are taken: the edges of the valid range")
    func integerDefaultsAtBounds() throws {
        let expected: [DebugDrawerScenarioValue] = [.integer(1), .integer(5)]

        let sut = try DebugDrawerScenarios(scenarios: [
            DebugDrawerScenario("onboarding", title: "Onboarding", parameters: [
                .integer("first", default: 1, in: 1 ... 5),
                .integer("last", default: 5, in: 1 ... 5)
            ]) { _ in }
        ])

        #expect(sut.snapshot.scenarios.first?.parameters.map(\.defaultValue) == expected)
    }

    @Test("A choice parameter with no options throws noOptions")
    func choiceWithoutOptions() {
        let expected = DebugDrawerScenarios.InvalidScenarios.noOptions

        #expect(throws: expected) {
            _ = try DebugDrawerScenarios(scenarios: [
                DebugDrawerScenario("paywall", title: "Paywall", parameters: [.choice("plan", options: [])]) { _ in }
            ])
        }
    }

    @Test("A choice parameter whose options repeat throws repeatedOption")
    func repeatedOption() {
        let expected = DebugDrawerScenarios.InvalidScenarios.repeatedOption

        #expect(throws: expected) {
            _ = try DebugDrawerScenarios(scenarios: [
                DebugDrawerScenario("paywall", title: "Paywall", parameters: [.choice("plan", options: ["annual", "annual"])]) { _ in }
            ])
        }
    }

    @Test("A choice parameter whose default isn't one of its options throws defaultNotAnOption")
    func choiceDefaultNotAnOption() {
        let expected = DebugDrawerScenarios.InvalidScenarios.defaultNotAnOption

        #expect(throws: expected) {
            _ = try DebugDrawerScenarios(scenarios: [
                DebugDrawerScenario("paywall", title: "Paywall", parameters: [
                    .choice("plan", options: ["monthly", "annual"], default: "lifetime")
                ]) { _ in }
            ])
        }
    }

    @Test("A choice parameter of one option with no default given starts at that option")
    func oneOptionChoice() throws {
        let expected = DebugDrawerScenarioValue.string("annual")

        let sut = try DebugDrawerScenarios(scenarios: [
            DebugDrawerScenario("paywall", title: "Paywall", parameters: [.choice("plan", options: ["annual"])]) { _ in }
        ])

        #expect(sut.snapshot.scenarios.first?.parameters.first?.defaultValue == expected)
    }

    @Test("A scenario with two parameters of one name, even of two kinds, throws duplicateParameterName")
    func repeatedParameterName() {
        let expected = DebugDrawerScenarios.InvalidScenarios.duplicateParameterName

        #expect(throws: expected) {
            _ = try DebugDrawerReceiverCapability.scenarios([
                DebugDrawerScenario("order", title: "Order", parameters: [.boolean("id"), .integer("id")]) { _ in }
            ])
        }
    }

    @Test("Two scenarios with one ID throw duplicateScenarioID")
    func repeatedScenarioID() {
        let expected = DebugDrawerScenarios.InvalidScenarios.duplicateScenarioID

        #expect(throws: expected) {
            _ = try DebugDrawerScenarios(scenarios: [
                DebugDrawerScenario("home", title: "Home") { _ in },
                DebugDrawerScenario("home", title: "Home Again") { _ in }
            ])
        }
    }

    @Test("Two scenarios may each declare a parameter of the same name")
    func sameParameterNameInTwoScenarios() throws {
        let expected = ["order", "refund"]

        let sut = try DebugDrawerScenarios(scenarios: [
            DebugDrawerScenario("order", title: "Order", parameters: [.integer("id")]) { _ in },
            DebugDrawerScenario("refund", title: "Refund", parameters: [.integer("id")]) { _ in }
        ])

        #expect(sut.snapshot.scenarios.map(\.id) == expected)
    }

    @Test("No scenarios are taken and list nothing")
    func noScenarios() throws {
        let sut = try DebugDrawerScenarios(scenarios: [])

        #expect(sut.snapshot.scenarios.isEmpty)
    }
}
