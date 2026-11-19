// ViewInspector is linked on Apple platforms only, and the views are tested on the Mac.
#if os(macOS)
    import DebugDrawer
    @testable import DebugDrawerUserDefaultsPlugin
    import Foundation
    import SwiftUI
    import Testing
    import ViewInspector

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct UserDefaultsPluginViewTests {
        @Test("The view draws the snapshot's filtered keys, and sends the suite picked, the filter and Reload as commands")
        func sendsCommands() throws {
            let group = UserDefaultsSuite.named("group.com.example.shared")
            var sent: [UserDefaultsCommand.Action] = []
            let sut = UserDefaultsPluginView(transport: DebugDrawerPluginTransport(
                initial: UserDefaultsSnapshot(
                    suites: [.standard, group],
                    entries: [
                        DefaultsEntry(key: "launchCount", value: .number(3)),
                        DefaultsEntry(key: "AppleLanguages", value: .array([.string("en")]), domain: .global)
                    ]
                ),
                snapshots: AsyncStream { $0.finish() },
                send: { sent.append($0.action) }
            ))
            let expected: [UserDefaultsCommand.Action] = [.selectSuite(group), .setSearchText("launch"), .reload]

            let view = try sut.inspect()
            try view.find(ViewType.Picker.self).select(value: group)
            try view.find(ViewType.TextField.self).setInput("launch")
            try view.find(button: "Reload").tap()

            #expect(sent == expected)
            #expect(throws: Never.self) { try view.find(text: "launchCount") }
            #expect((try? view.find(text: "AppleLanguages")) == nil)
        }

        @Test("The header counts the keys the filters let through")
        func headerCount() throws {
            let sut = UserDefaultsHeaderAccessory(transport: DebugDrawerPluginTransport(
                initial: UserDefaultsSnapshot(entries: [
                    DefaultsEntry(key: "a", value: .string("x")),
                    DefaultsEntry(key: "b", value: .string("y")),
                    DefaultsEntry(key: "c", value: .string("z"), domain: .registration)
                ]),
                snapshots: AsyncStream { $0.finish() },
                send: { _ in }
            ))

            let actual = try sut.inspect().text().string()

            #expect(actual == "2 keys")
        }
    }
#endif
