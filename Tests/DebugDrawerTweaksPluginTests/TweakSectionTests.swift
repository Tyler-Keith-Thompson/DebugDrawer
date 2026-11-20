#if DEBUG
    @testable import DebugDrawerTweaksPlugin
    import Testing

    @Suite
    struct TweakSectionTests {
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
