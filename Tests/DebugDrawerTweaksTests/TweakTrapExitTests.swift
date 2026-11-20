// Exit tests start a child process, which only the Mac's test runs can do.
#if os(macOS) && DEBUG
    @testable import DebugDrawerTweaks
    import Testing

    @Suite
    struct TweakTrapExitTests {
        @Test("A stepper whose default is outside its range traps")
        func stepperDefaultOutsideRange() async {
            await #expect(processExitsWith: .failure) {
                _ = Tweak.stepper("Timeout", key: "timeout", default: 0, in: 1 ... 10)
            }
        }

        @Test("A stepper whose step isn't positive traps")
        func stepperStepNotPositive() async {
            await #expect(processExitsWith: .failure) {
                _ = Tweak.stepper("Timeout", key: "timeout", default: 5, in: 1 ... 10, step: 0)
            }
        }

        @Test("A string picker whose default isn't one of its options traps")
        func pickerDefaultNotAnOption() async {
            await #expect(processExitsWith: .failure) {
                _ = Tweak.picker("Region", key: "region", options: ["us", "eu"], default: "apac")
            }
        }

        @Test("A string picker with no options traps")
        func pickerNoOptions() async {
            await #expect(processExitsWith: .failure) {
                _ = Tweak.picker("Region", key: "region", options: [], default: "us")
            }
        }
    }
#endif
