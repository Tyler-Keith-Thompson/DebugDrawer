// ViewInspector is linked on Apple platforms only, and the views are tested on the Mac.
#if os(macOS)
    @testable import DebugDrawerConsolePlugin
    import SwiftUI
    import Testing
    import ViewInspector

    @MainActor
    @Suite
    struct ConsoleDroppedHintTests {
        @Test("Once lines were dropped, the hint says how many")
        func counts() {
            let sut = ConsoleDroppedHint(count: 12)

            #expect(throws: Never.self) { try sut.inspect().find(text: "12 older lines dropped") }
        }

        @Test("One dropped line reads in the singular")
        func singular() {
            let sut = ConsoleDroppedHint(count: 1)

            #expect(throws: Never.self) { try sut.inspect().find(text: "1 older line dropped") }
        }

        @Test("With no lines dropped, the hint shows nothing")
        func hidden() throws {
            let sut = ConsoleDroppedHint(count: 0)

            let actual = try sut.inspect().findAll(ViewType.Text.self)

            #expect(actual.isEmpty)
        }
    }
#endif
