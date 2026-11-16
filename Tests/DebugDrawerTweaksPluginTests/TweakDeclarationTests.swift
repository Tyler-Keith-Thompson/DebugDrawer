#if DEBUG
    @testable import DebugDrawerTweaksPlugin
    import Testing

    @Suite
    struct TweakDeclarationTests {
        @Test("A toggle reads its default until something is stored, then the stored Boolean")
        func toggle() {
            let sut = Tweak.toggle("New checkout", key: "newCheckout", default: false)
            let stored = TweakStoredValue.bool(true)

            #expect(sut.value(from: nil) == false)
            #expect(sut.value(from: stored) == true)
            #expect(sut.storedValue(of: true) == stored)
        }

        @Test("A value of another type reads as the default")
        func otherType() {
            let sut = Tweak.toggle("New checkout", key: "newCheckout", default: true)
            let stored = TweakStoredValue.string("true")

            let actual = sut.value(from: stored)

            #expect(actual == true)
        }

        @Test("Empty text is a value of its own, not the default")
        func emptyText() {
            let sut = Tweak.text("Greeting", key: "greeting", default: "Hello")
            let stored = TweakStoredValue.string("")
            let expected = ""

            let actual = sut.value(from: stored)

            #expect(actual == expected)
        }

        @Test("A string picker reads a stored option, and a string that is no longer an option as its default")
        func stringPicker() {
            let sut = Tweak.picker("Region", key: "region", options: ["us", "eu"], default: "us")
            let known = TweakStoredValue.string("eu")
            let removed = TweakStoredValue.string("apac")

            #expect(sut.value(from: known) == "eu")
            #expect(sut.value(from: removed) == "us")
            #expect(sut.control == .picker([
                TweakOption(title: "us", value: .string("us")),
                TweakOption(title: "eu", value: .string("eu"))
            ]))
        }

        @Test("An enumeration picker stores raw values, shows case names, and reads an unknown raw value as its default")
        func enumPicker() {
            let sut = Tweak.picker("Server", key: "server", default: Server.production)
            let expectedControl = TweakControl.picker([
                TweakOption(title: "production", value: .string("production")),
                TweakOption(title: "staging", value: .string("staging")),
                TweakOption(title: "local", value: .string("local"))
            ])

            #expect(sut.storedValue(of: .staging) == .string("staging"))
            #expect(sut.value(from: .string("staging")) == .staging)
            #expect(sut.value(from: .string("qa")) == .production)
            #expect(sut.control == expectedControl)
        }

        @Test("An integer-backed enumeration picker stores raw integers")
        func intEnumPicker() {
            let sut = Tweak.picker("Retries", key: "retries", default: RetryPolicy.few)

            #expect(sut.storedValue(of: .many) == .int(10))
            #expect(sut.value(from: .int(0)) == .never)
            #expect(sut.value(from: .int(7)) == .few)
        }

        @Test("A stepper reads a stored value outside its range as the nearest bound", arguments: [
            (-5, 1), (1, 1), (4, 4), (10, 10), (99, 10)
        ])
        func stepperClamps(stored: Int, expected: Int) {
            let sut = Tweak.stepper("Timeout", key: "timeout", default: 5, in: 1 ... 10)

            let actual = sut.value(from: .int(stored))

            #expect(actual == expected)
        }

        @Test("A stepper's range of one value reads only that value")
        func stepperSingleValue() {
            let sut = Tweak.stepper("Workers", key: "workers", default: 3, in: 3 ... 3)

            #expect(sut.value(from: .int(1)) == 3)
            #expect(sut.value(from: .int(9)) == 3)
            #expect(sut.control == .stepper(range: 3 ... 3, step: 1))
        }

        @Test("A tweak is not production-safe unless marked, and the mark changes nothing else")
        func productionSafe() {
            let plain = Tweak.toggle("New checkout", key: "newCheckout", default: false)

            let actual = plain.productionSafe()

            #expect(!plain.isProductionSafe)
            #expect(actual.isProductionSafe)
            #expect(!actual.productionSafe(false).isProductionSafe)
            #expect(actual.title == plain.title)
            #expect(actual.key == plain.key)
            #expect(actual.defaultValue == plain.defaultValue)
        }

        @Test("A section lists its tweaks and actions in order, with if and for")
        func sectionBuilder() {
            let includeDebugOnly = false
            let sut = TweakSection("Server") {
                Tweak.picker("Server", key: "server", default: Server.production).productionSafe()
                Tweak.stepper("Timeout", key: "timeout", default: 30, in: 5 ... 120, step: 5)
                if includeDebugOnly {
                    Tweak.toggle("Verbose", key: "verbose", default: false)
                }
                for index in 1 ... 2 {
                    Tweak.text("Header \(index)", key: "header\(index)", default: "")
                }
                TweakAction("Expire token") {}
            }
            let expectedKeys = ["server", "timeout", "header1", "header2"]

            #expect(sut.title == "Server")
            #expect(sut.tweaks.map(\.key) == expectedKeys)
            #expect(sut.tweaks.map(\.isProductionSafe) == [true, false, false, false])
            #expect(sut.actions.map(\.title) == ["Expire token"])
        }
    }
#endif
