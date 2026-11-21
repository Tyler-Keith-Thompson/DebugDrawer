#if DEBUG
    #if os(macOS)
        import AppKit
    #endif
    import Combine
    @testable import DebugDrawer
    import DebugDrawerTestSupport
    import Foundation
    import SwiftUI
    import Testing
    #if !os(visionOS)
        import ViewInspector
    #endif

    /// A local plugin showing the user its screen shows.
    private struct UserPlugin: DebugDrawerPlugin {
        let id = "local-refresh.user"
        let user: String
        var title = "User"
        var icon = "person"
        var body: some View { Text(user) }
    }

    // Each test makes a drawer of its own over a UserDefaults suite named for the test, removed
    // when the test ends.
    @MainActor
    @Suite("Local plugins follow their view")
    struct LocalPluginRefreshTests {
        @Test("A local plugin listed alike shows its latest value without the drawer listing it again")
        func aNewValueReachesTheListedPlugin() throws {
            let suite = temporarySuiteName("LocalPluginRefreshTests.\(#function)")
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let sut = DebugDrawer(defaults: defaults)
            let token = sut.registerLocal(UserPlugin(user: "Ada"))
            let listed = try #require(sut.localPlugins.first)
            var listChanges = 0
            let subscription = sut.objectWillChange.sink { listChanges += 1 }
            defer { subscription.cancel() }

            sut.updateLocal(UserPlugin(user: "Grace"), token: token)

            #expect(listChanges == 0)
            #if !os(visionOS)
                #expect(throws: Never.self) { try listed.body.inspect().find(text: "Grace") }
            #endif
        }

        @Test("A local plugin whose title changes is listed again under the new title")
        func aNewTitleIsListedAgain() throws {
            let suite = temporarySuiteName("LocalPluginRefreshTests.\(#function)")
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let sut = DebugDrawer(defaults: defaults)
            let token = sut.registerLocal(UserPlugin(user: "Ada", title: "Ada's Account"))
            let expected = ["Grace's Account"]

            sut.updateLocal(UserPlugin(user: "Grace", title: "Grace's Account"), token: token)

            #expect(sut.localPlugins.map(\.title) == expected)
        }

        @Test("A value handed over after the view left registers nothing")
        func anUpdateAfterRemovalIsIgnored() throws {
            let suite = temporarySuiteName("LocalPluginRefreshTests.\(#function)")
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let sut = DebugDrawer(defaults: defaults)
            let token = sut.registerLocal(UserPlugin(user: "Ada"))
            sut.unregisterLocal(id: "local-refresh.user", token: token)

            sut.updateLocal(UserPlugin(user: "Grace"), token: token)

            #expect(sut.localPlugins.isEmpty)
        }
    }

    #if os(macOS)
        // debugLocalPlugin(_:) registers with the shared drawer, so this test stays on it, in the
        // serialized suite of the shared drawer's tests.
        extension SharedDrawerTests {
            @MainActor
            @Suite("Local plugins follow their view, from SwiftUI")
            struct SharedDrawerLocalPluginRefreshTests {
                @Test("debugLocalPlugin shows the plugin's new value once its input changes, with no contentIdentifier")
                func theModifierFollowsItsInput() throws {
                    let screen = UserScreen.Model()
                    let window = NSWindow(
                        contentRect: CGRect(x: -30000, y: -30000, width: 400, height: 300),
                        styleMask: .borderless, backing: .buffered, defer: false
                    )
                    window.isReleasedWhenClosed = false
                    let host = NSHostingView(rootView: UserScreen(model: screen))
                    window.contentView = host
                    window.orderFront(nil)
                    defer {
                        window.close()
                        // The screen attaches no drawer, so closing its window forgets nothing.
                        DebugDrawer.shared.localRegistrations.removeAll { $0.plugin.id == "local-refresh.user" }
                    }
                    host.layoutSubtreeIfNeeded()
                    let listed = try #require(DebugDrawer.shared.localPlugins.first { $0.id == "local-refresh.user" })
                    #expect(throws: Never.self) { try listed.body.inspect().find(text: "Ada") }

                    screen.user = "Grace"
                    host.layoutSubtreeIfNeeded()

                    let actual = try #require(DebugDrawer.shared.localPlugins.first { $0.id == "local-refresh.user" })
                    #expect(throws: Never.self) { try actual.body.inspect().find(text: "Grace") }
                    #expect(throws: (any Error).self) { try actual.body.inspect().find(text: "Ada") }
                }
            }
        }

        /// A screen showing a user, with the user's plugin attached.
        private struct UserScreen: View {
            @MainActor
            final class Model: ObservableObject {
                @Published var user = "Ada"
            }

            @ObservedObject var model: Model

            var body: some View {
                Text(model.user)
                    .debugLocalPlugin(UserPlugin(user: model.user))
            }
        }
    #endif
#endif
