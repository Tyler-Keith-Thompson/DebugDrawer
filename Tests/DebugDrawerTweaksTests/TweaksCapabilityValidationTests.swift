#if DEBUG
    import DebugDrawerReceiver
    @testable import DebugDrawerTweaks
    import Foundation
    import Testing

    // What the receiver's tweaks capability refuses as it is made, in every build: declarations it
    // couldn't serve. Each is made through the public spelling with storage of the test's own, so a
    // capability that took it anyway would show as the shared store reading that storage; a
    // refusal must leave the shared store and the receiver as they were.
    @MainActor
    @Suite
    struct TweaksCapabilityValidationTests {
        @Test("Two tweaks sharing a key throw duplicateKey, and the shared tweaks keep their storage")
        func duplicateKeys() {
            let storage = FakeTweakStorage()
            let first = Tweak.toggle("A", key: "shared", default: false).productionSafe()
            let second = Tweak.text("B", key: "shared", default: "")

            #expect(throws: TweaksModel.InvalidTweaks.duplicateKey) {
                _ = try DebugDrawerReceiverCapability.tweaks(first, second, storage: storage)
            }
            #expect((TweakStore.shared.storage as? FakeTweakStorage) !== storage)
        }

        @Test("A string picker whose default isn't one of its options throws pickerDefaultNotAnOption")
        func pickerDefaultNotAnOption() {
            let storage = FakeTweakStorage()
            let region = Tweak.picker("Region", key: "region", options: ["us", "eu"], default: "apac").productionSafe()

            #expect(throws: TweaksModel.InvalidTweaks.pickerDefaultNotAnOption) {
                _ = try DebugDrawerReceiverCapability.tweaks(region, storage: storage)
            }
            #expect((TweakStore.shared.storage as? FakeTweakStorage) !== storage)
        }

        @Test("A string picker with no options throws pickerDefaultNotAnOption")
        func pickerNoOptions() {
            let storage = FakeTweakStorage()
            let region = Tweak.picker("Region", key: "region", options: [], default: "us").productionSafe()

            #expect(throws: TweaksModel.InvalidTweaks.pickerDefaultNotAnOption) {
                _ = try DebugDrawerReceiverCapability.tweaks(region, storage: storage)
            }
            #expect((TweakStore.shared.storage as? FakeTweakStorage) !== storage)
        }

        @Test("A stepper whose default is above its range throws stepperDefaultOutOfRange, before its step is looked at")
        func stepperDefaultAboveRange() {
            let storage = FakeTweakStorage()
            let timeout = Tweak.stepper("Timeout", key: "timeout", default: 500, in: 5 ... 120, step: 0).productionSafe()

            #expect(throws: TweaksModel.InvalidTweaks.stepperDefaultOutOfRange) {
                _ = try DebugDrawerReceiverCapability.tweaks(timeout, storage: storage)
            }
            #expect((TweakStore.shared.storage as? FakeTweakStorage) !== storage)
        }

        @Test("A stepper whose default is one below its range throws stepperDefaultOutOfRange")
        func stepperDefaultBelowRange() {
            let storage = FakeTweakStorage()
            let timeout = Tweak.stepper("Timeout", key: "timeout", default: 4, in: 5 ... 120).productionSafe()

            #expect(throws: TweaksModel.InvalidTweaks.stepperDefaultOutOfRange) {
                _ = try DebugDrawerReceiverCapability.tweaks(timeout, storage: storage)
            }
            #expect((TweakStore.shared.storage as? FakeTweakStorage) !== storage)
        }

        @Test("A stepper whose step is 0 throws stepperStepNotPositive")
        func stepperStepZero() {
            let storage = FakeTweakStorage()
            let timeout = Tweak.stepper("Timeout", key: "timeout", default: 30, in: 5 ... 120, step: 0).productionSafe()

            #expect(throws: TweaksModel.InvalidTweaks.stepperStepNotPositive) {
                _ = try DebugDrawerReceiverCapability.tweaks(timeout, storage: storage)
            }
            #expect((TweakStore.shared.storage as? FakeTweakStorage) !== storage)
        }

        @Test("A stepper whose step is negative throws stepperStepNotPositive")
        func stepperStepNegative() {
            let storage = FakeTweakStorage()
            let timeout = Tweak.stepper("Timeout", key: "timeout", default: 30, in: 5 ... 120, step: -5).productionSafe()

            #expect(throws: TweaksModel.InvalidTweaks.stepperStepNotPositive) {
                _ = try DebugDrawerReceiverCapability.tweaks(timeout, storage: storage)
            }
            #expect((TweakStore.shared.storage as? FakeTweakStorage) !== storage)
        }

        @Test("A tweak that isn't production-safe is checked too: its bad default throws though a sidecar would never see it")
        func unmarkedTweakChecked() {
            let storage = FakeTweakStorage()
            let backend = Tweak.picker("Backend", key: "backend", default: Server.production).productionSafe()
            let retries = Tweak.stepper("Retries", key: "retries", default: 0, in: 1 ... 5)

            #expect(throws: TweaksModel.InvalidTweaks.stepperDefaultOutOfRange) {
                _ = try DebugDrawerReceiverCapability.tweaks(backend, retries, storage: storage)
            }
            #expect((TweakStore.shared.storage as? FakeTweakStorage) !== storage)
        }

        @Test("A refused list enables nothing on the receiver")
        func receiverEnablesNothing() {
            let directory = FileManager.default.temporaryDirectory.appending(path: "TweaksCapabilityValidationTests-\(UUID().uuidString)")
            let sut = DebugDrawerReceiver(directory: directory, sessions: DebugDrawerSessions(maximumDuration: 300))
            let timeout = Tweak.stepper("Timeout", key: "timeout", default: 500, in: 5 ... 120, step: 0).productionSafe()

            #expect(throws: TweaksModel.InvalidTweaks.stepperDefaultOutOfRange) {
                try sut.enable(.tweaks(timeout, storage: FakeTweakStorage()))
            }
            #expect(sut.enabledCapabilities.isEmpty)
        }

        @Test("A model refused over a store of the test's own offers that store nothing")
        func modelOffersNothing() {
            let sut = TweakStore(storage: FakeTweakStorage(), reading: .offeredProductionSafeTweaks)
            let timeout = Tweak.stepper("Timeout", key: "timeout", default: 30, in: 5 ... 120, step: 0).productionSafe()

            #expect(throws: TweaksModel.InvalidTweaks.stepperStepNotPositive) {
                _ = try TweaksModel(tweaks: [AnyTweak(timeout)], store: sut)
            }
            #expect(!sut.offersProductionSafeTweaks)
        }

        @Test("Steppers whose defaults are the bounds of their ranges, and a picker's default among its options, are taken")
        func boundsTaken() throws {
            let sut = TweakStore(storage: FakeTweakStorage(), reading: .offeredProductionSafeTweaks)
            let lowest = Tweak.stepper("Timeout", key: "timeout", default: 5, in: 5 ... 120, step: 5).productionSafe()
            let highest = Tweak.stepper("Retries", key: "retries", default: 10, in: 1 ... 10).productionSafe()
            let region = Tweak.picker("Region", key: "region", options: ["us"], default: "us").productionSafe()
            let expected = ["timeout", "retries", "region"]

            let actual = try TweaksModel(tweaks: [AnyTweak(lowest), AnyTweak(highest), AnyTweak(region)], store: sut).snapshot.tweaks.map(\.key)

            #expect(actual == expected)
        }
    }
#endif
