#if DEBUG
    import Combine
    @testable import DebugDrawerReceiver
    @testable import DebugDrawerTweaks
    import Foundation
    import Testing

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct TweaksModelTests {
        @Test("The model keeps only production-safe tweaks, in the order listed")
        func keepsProductionSafeInOrder() throws {
            let timeout = Tweak.stepper("Timeout", key: "timeout", default: 30, in: 5 ... 120).productionSafe()
            let verbose = Tweak.toggle("Verbose logging", key: "verbose", default: false)
            let greeting = Tweak.text("Greeting", key: "greeting", default: "Hi").productionSafe()
            let expectedKeys = ["timeout", "greeting"]
            let expectedTitles = ["Timeout", "Greeting"]

            let sut = try TweaksModel(
                tweaks: [AnyTweak(timeout), AnyTweak(verbose), AnyTweak(greeting)],
                store: TweakStore(storage: FakeTweakStorage(), reading: .everyTweak)
            )

            #expect(sut.snapshot.tweaks.map(\.key) == expectedKeys)
            #expect(sut.snapshot.tweaks.map(\.title) == expectedTitles)
        }

        @Test("Two production-safe tweaks sharing a key throw duplicateKey when the model is made")
        func duplicateKeyThrows() {
            let store = TweakStore(storage: FakeTweakStorage(), reading: .everyTweak)
            let greeting = Tweak.text("Greeting", key: "greeting", default: "Hi").productionSafe()
            let duplicate = Tweak.text("Other greeting", key: "greeting", default: "Hello").productionSafe()

            #expect(throws: TweaksModel.InvalidTweaks.duplicateKey) {
                _ = try TweaksModel(tweaks: [AnyTweak(greeting), AnyTweak(duplicate)], store: store)
            }
        }

        @Test("With no production-safe tweak, the snapshot is empty and every key is refused as not exposed")
        func noneProductionSafe() throws {
            let verbose = Tweak.toggle("Verbose logging", key: "verbose", default: false)
            let sut = try TweaksModel(tweaks: [AnyTweak(verbose)], store: TweakStore(storage: FakeTweakStorage(), reading: .everyTweak))

            #expect(sut.snapshot.tweaks.isEmpty)
            #expect(sut.refusal(of: .setValue(key: "verbose", value: .bool(true))) == .notExposed)
            #expect(sut.refusal(of: .reset(key: "verbose")) == .notExposed)
            #expect(sut.refusal(of: .reset(key: "unknown")) == .notExposed)
            #expect(sut.refusal(of: .resetAll) == nil)
        }

        @Test("A stepper takes its bounds and refuses a value one past them")
        func stepperBounds() throws {
            let timeout = Tweak.stepper("Timeout", key: "timeout", default: 30, in: 5 ... 120).productionSafe()
            let sut = try TweaksModel(tweaks: [AnyTweak(timeout)], store: TweakStore(storage: FakeTweakStorage(), reading: .everyTweak))

            #expect(sut.refusal(of: .setValue(key: "timeout", value: .int(5))) == nil)
            #expect(sut.refusal(of: .setValue(key: "timeout", value: .int(120))) == nil)
            #expect(sut.refusal(of: .setValue(key: "timeout", value: .int(4))) == .malformedCommand)
            #expect(sut.refusal(of: .setValue(key: "timeout", value: .int(121))) == .malformedCommand)
        }

        @Test("Performed directly, a command to an unmarked tweak changes nothing, while one to a production-safe tweak stores its value")
        func performGuardsUnmarked() throws {
            let storage = FakeTweakStorage()
            let greeting = Tweak.text("Greeting", key: "greeting", default: "Hi").productionSafe()
            let verbose = Tweak.toggle("Verbose logging", key: "verbose", default: false)
            let sut = try TweaksModel(tweaks: [AnyTweak(greeting), AnyTweak(verbose)], store: TweakStore(storage: storage, reading: .everyTweak))
            let expected: [String: TweakStoredValue] = ["greeting": .string("")]

            sut.perform(.setValue(key: "verbose", value: .bool(true)))
            sut.perform(.setValue(key: "greeting", value: .string("")))

            #expect(storage.values == expected)
            #expect(sut.snapshot.tweaks.map(\.value) == [.string("")])
        }

        @Test("A change made through the store, as the drawer makes it, shows in the model's snapshot")
        func followsStore() throws {
            let greeting = Tweak.text("Greeting", key: "greeting", default: "Hi").productionSafe()
            let store = TweakStore(storage: FakeTweakStorage(), reading: .everyTweak)
            let sut = try TweaksModel(tweaks: [AnyTweak(greeting)], store: store)

            store.set("Welcome", for: greeting)

            #expect(sut.snapshot.tweaks.map(\.value) == [.string("Welcome")])
        }

        @Test("Values, controls and commands encode as a sidecar reads and sends them")
        func wireFormat() throws {
            let command = TweaksModel.Command.setValue(key: "timeout", value: .int(60))
            let control = TweakControl.stepper(range: 5 ... 120, step: 5)
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys

            let encodedValues = try [TweakStoredValue.bool(true), .int(3), .string("staging")].map {
                try String(bytes: encoder.encode($0), encoding: .utf8)
            }
            let decodedValues = try ["true", "3", "\"3\""].map { try JSONDecoder().decode(TweakStoredValue.self, from: Data($0.utf8)) }
            let decodedCommand = try JSONDecoder().decode(TweaksModel.Command.self, from: encoder.encode(command))
            let decodedControl = try JSONDecoder().decode(TweakControl.self, from: encoder.encode(control))

            #expect(encodedValues == ["true", "3", "\"staging\""])
            #expect(decodedValues == [.bool(true), .int(3), .string("3")])
            #expect(decodedCommand == command)
            #expect(decodedControl == control)
            #expect(throws: DecodingError.self) { try JSONDecoder().decode(TweakStoredValue.self, from: Data("2.5".utf8)) }
        }
    }
#endif
