// Views render on the Mac; ViewInspector is linked on Apple platforms only.
#if os(macOS)
    @testable import DebugDrawer
    import SwiftUI
    import Testing
    import ViewInspector

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct CodeTextTests {
        @Test("A path shows on one line, cut in the middle, until tapped; tapped again it returns to one line")
        func expands() async throws {
            let path = "/Applications/Example.app/Contents/Frameworks/Charts.framework/Versions/A/Charts"
            let sut = DebugDrawerCodeText(path)

            try await ViewHosting.host(sut) {
                try await sut.inspection.inspect { view in
                    let text = try view.find(ViewType.Text.self)
                    #expect(try text.string() == path)
                    #expect(try text.lineLimit() == 1)
                    #expect(try text.truncationMode() == .middle)
                    try text.callOnTapGesture()
                }
                try await sut.inspection.inspect { view in
                    let text = try view.find(ViewType.Text.self)
                    #expect(try text.lineLimit() == nil)
                    try text.callOnTapGesture()
                }
                try await sut.inspection.inspect { view in
                    let lineLimit = try view.find(ViewType.Text.self).lineLimit()
                    #expect(lineLimit == 1)
                }
            }
        }

        @Test("A key-value row shows a figure and its unit as one value")
        func measuredValue() throws {
            let sut = DebugDrawerKeyValueRow("Footprint", value: "63.5 MB")
            let expected = ["Footprint", "63.5 MB"]

            let actual = try sut.inspect().findAll(ViewType.Text.self).map { try $0.string() }

            #expect(actual.prefix(2) == expected[...])
        }

        @Test("A key-value row keeps an identifier whole on one line, cut in the middle if it must be")
        func identifierValue() throws {
            let sut = DebugDrawerKeyValueRow("Bundle ID", value: "com.debugdrawer.example.ios")
            let expected = "com.debugdrawer.example.ios"

            let text = try sut.inspect().find(text: expected)

            #expect(try text.lineLimit() == 1)
            #expect(try text.truncationMode() == .middle)
        }
    }
#endif
