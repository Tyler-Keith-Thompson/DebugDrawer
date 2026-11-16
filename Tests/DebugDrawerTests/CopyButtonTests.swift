// Views render on the Mac; ViewInspector is linked on Apple platforms only.
#if os(macOS)
    import AppKit
    @testable import DebugDrawer
    import SwiftUI
    import Testing
    import ViewInspector

    // The tests read and write the general pasteboard, which every test in the process shares, so
    // they run one at a time.
    @MainActor
    @Suite(.serialized, .timeLimit(.minutes(1)))
    struct CopyButtonTests {
        @Test("The button shows its title and says that it copies")
        func title() throws {
            let sut = DebugDrawerCopyButton("Copy Info") { "report" }
            let expectedTitle = "Copy Info"
            let expectedHint = "Copies to the clipboard"

            let button = try sut.inspect().find(ViewType.Button.self)
            let actualTitle = try button.labelView().text().string()
            let actualHint = try button.accessibilityHint().string()

            #expect(actualTitle == expectedTitle)
            #expect(actualHint == expectedHint)
        }

        @Test("Pressing the button copies its value to the clipboard")
        func copies() throws {
            let expected = "Launch Time Report \(UUID().uuidString)"
            let sut = DebugDrawerCopyButton("Copy") { expected }

            try sut.inspect().find(ViewType.Button.self).tap()

            let actual = NSPasteboard.general.string(forType: .string)
            #expect(actual == expected)
        }

        @Test("The value is read when the button is pressed, not when it is drawn")
        func readsOnPress() throws {
            var reads = 0
            func value() -> String? {
                reads += 1
                return "value"
            }
            let sut = DebugDrawerCopyButton("Copy", value: value)

            let button = try sut.inspect().find(ViewType.Button.self)
            let readsBeforePress = reads
            try button.tap()

            #expect(readsBeforePress == 0)
            #expect(reads == 1)
        }

        @Test("A button whose value is nil copies nothing and leaves the clipboard as it was")
        func nilCopiesNothing() throws {
            let expected = "Already on the clipboard \(UUID().uuidString)"
            debugDrawerCopyToClipboard(expected)
            let sut = DebugDrawerCopyButton("Copy Value") { nil }

            try sut.inspect().find(ViewType.Button.self).tap()

            let actual = NSPasteboard.general.string(forType: .string)
            #expect(actual == expected)
        }
    }
#endif
