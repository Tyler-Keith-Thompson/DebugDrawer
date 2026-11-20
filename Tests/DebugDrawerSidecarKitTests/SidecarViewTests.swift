#if DEBUG && os(macOS)
    import DebugDrawer
    @testable import DebugDrawerSidecarKit
    import Foundation
    import SwiftUI
    import Testing
    import ViewInspector

    // The kit's views as functions of their input: the sidebar for a list of apps, an empty list
    // and a group not reached, and the session's state.
    @MainActor
    @Suite
    struct SidecarViewTests {
        static let shop = DebugDrawerSidecarApp(
            bundleIdentifier: "com.example.shop", displayName: "Shop", version: "2.4", build: "881",
            capabilities: ["ConsolePlugin", "DebugDrawer.Sessions"], lastSeen: Date(), storeDirectory: URL(filePath: "/tmp/store")
        )
        static let wallet = DebugDrawerSidecarApp(
            bundleIdentifier: "com.example.wallet", displayName: "Wallet", version: "1.0", build: "",
            capabilities: [], lastSeen: Date(), storeDirectory: URL(filePath: "/tmp/store")
        )

        @Test("The sidebar lists each app with its version and bundle ID, and one turned off by its host says so")
        func sidebarListsApps() throws {
            let sut = SidecarAppListView(apps: [Self.shop, Self.wallet], error: nil, selection: .constant(nil))

            let view = try sut.inspect()

            #expect(throws: Never.self) { try view.find(text: "Shop") }
            #expect(throws: Never.self) { try view.find(text: "2.4 (881)") }
            #expect(throws: Never.self) { try view.find(text: "com.example.shop") }
            #expect(throws: Never.self) { try view.find(text: "Wallet") }
            #expect(throws: Never.self) { try view.find(text: "1.0") }
            #expect(throws: Never.self) { try view.find(text: "Turned off by the host") }
        }

        @Test("An empty sidebar says no app serves a sidecar; a group not reached says why")
        func sidebarEmptyAndUnreachable() throws {
            let empty = SidecarAppListView(apps: [], error: nil, selection: .constant(nil))
            let unreachable = SidecarAppListView(apps: [], error: .noAppGroupContainer, selection: .constant(nil))

            let emptyView = try empty.inspect()
            let unreachableView = try unreachable.inspect()

            #expect(throws: Never.self) { try emptyView.find(text: "No Apps") }
            #expect(throws: Never.self) { try unreachableView.find(text: "Group Not Reachable") }
            #expect(throws: Never.self) { try unreachableView.find(text: DebugDrawerTransportError.noAppGroupContainer.localizedDescription) }
        }

        @Test("With no session the status says the app refuses commands; with one, until when")
        func sessionStatus() throws {
            let session = DebugDrawerSession(
                id: UUID(), opened: Date(timeIntervalSince1970: 1_800_000_000), expires: Date(timeIntervalSince1970: 1_800_000_600)
            )
            let inactive = SidecarSessionStatus(state: .inactive)
            let active = SidecarSessionStatus(state: .active(session))

            let inactiveView = try inactive.inspect()
            let activeText = try active.inspect().find(ViewType.Text.self).string()

            #expect(throws: Never.self) { try inactiveView.find(text: "No session: the app refuses commands") }
            #expect(activeText.hasPrefix("Session until "))
        }

        @Test("The session control offers Open Session while none is open, and End Session while one is")
        func sessionControlButtons() throws {
            let session = DebugDrawerSession(id: UUID(), opened: Date(), expires: Date().addingTimeInterval(600))
            let closed = SidecarSessionRow(
                sessions: DebugDrawerPluginTransport(initial: .inactive, snapshots: AsyncStream { $0.finish() }) { _ in },
                open: { nil }, end: {}
            )
            var ended = false
            let open = SidecarSessionRow(
                sessions: DebugDrawerPluginTransport(initial: .active(session), snapshots: AsyncStream { $0.finish() }) { _ in },
                open: { nil }, end: { ended = true }
            )

            let closedView = try closed.inspect()
            try open.inspect().find(button: "End Session").tap()

            #expect(throws: Never.self) { try closedView.find(button: "Open Session") }
            #expect((try? closedView.find(button: "End Session")) == nil)
            #expect(ended)
        }
    }
#endif
