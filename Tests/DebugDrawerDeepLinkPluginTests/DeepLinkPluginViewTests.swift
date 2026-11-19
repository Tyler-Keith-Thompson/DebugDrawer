// ViewInspector is linked on Apple platforms only, and the views are tested on the Mac.
#if os(macOS)
    import DebugDrawer
    @testable import DebugDrawerDeepLinkPlugin
    import Foundation
    import SwiftUI
    import Testing
    import ViewInspector

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct DeepLinkPluginViewTests {
        @Test("The view draws the snapshot, and sends typing, Continue and Clear History as commands")
        func sendsCommands() throws {
            let url = try #require(URL(string: "https://example.com/orders/42"))
            var sent: [DeepLinkCommand.Action] = []
            let sut = DeepLinkPluginView(transport: DebugDrawerPluginTransport(
                initial: DeepLinkSnapshot(
                    urlText: "https://example.com/orders/42", history: ["myapp://orders/7"], outcome: .opened("myapp://orders/7")
                ),
                snapshots: AsyncStream { $0.finish() },
                send: { sent.append($0.action) }
            ))
            let expected: [DeepLinkCommand.Action] = [
                .setURLText("https://example.com/orders/43"),
                .continue(.universalLink(url)),
                .clearHistory
            ]

            let view = try sut.inspect()
            try view.find(ViewType.TextField.self).setInput("https://example.com/orders/43")
            try view.find(button: "Continue").tap()
            try view.find(button: "Clear History").tap()

            #expect(sent == expected)
            #expect(throws: Never.self) { try view.find(text: "Opened by the system: myapp://orders/7") }
            #expect(throws: Never.self) { try view.find(text: "History (1)") }
        }
    }
#endif
