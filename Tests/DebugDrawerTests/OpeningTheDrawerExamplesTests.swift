// The triggers of InstallingInSwiftUI.md's "Open the drawer" example, each placed in a view, a
// window or the application so it compiles as written there, and its "When another framework
// makes the window" example.

#if DEBUG
    import DebugDrawer
    import SwiftUI
    import Testing

    #if os(macOS) || os(iOS)
        struct ShortcutTriggerExample: View {
            var body: some View {
                Text("Home")
                    // A keyboard shortcut of the app's own (Ctrl-D here)
                    .background {
                        Button("") { DebugDrawer.shared.toggle() }
                            .keyboardShortcut("d", modifiers: .control)
                            .hidden()
                    }
            }
        }

        struct TripleTapTriggerExample: View {
            var body: some View {
                Text("Home")
                    // Triple-tap (iOS)
                    .onTapGesture(count: 3) { DebugDrawer.shared.toggle() }
            }
        }
    #endif

    #if os(iOS)
        import UIKit

        final class ShakeTriggerWindowExample: UIWindow {
            // Shake gesture (iOS)
            override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
                if motion == .motionShake { DebugDrawer.shared.toggle() }
            }
        }

        // Mac Catalyst compiles these as iOS does; a Mac sends no shake, so they never fire there.
        // Shake gesture with no responder of the app's own (iOS): the UIApplication subclass
        // that Info.plist's NSPrincipalClass names, here "OrdersApplication"
        @objc(OrdersApplication)
        final class OrdersApplication: UIApplication {
            override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
                super.motionEnded(motion, with: event)
                if motion == .motionShake { DebugDrawer.shared.toggle() }
            }
        }

        // InstallingInSwiftUI.md, "When another framework makes the window"
        @MainActor
        final class DebugDrawerAttacher {
            static let shared = DebugDrawerAttacher()
            private var activation: (any NSObjectProtocol)?

            func attachEveryScene() {
                for case let windowScene as UIWindowScene in UIApplication.shared.connectedScenes {
                    DebugDrawer.shared.attach(to: windowScene)
                }
                guard activation == nil else { return }
                activation = NotificationCenter.default.addObserver(
                    forName: UIScene.didActivateNotification, object: nil, queue: .main
                ) { notification in
                    guard let windowScene = notification.object as? UIWindowScene else { return }
                    MainActor.assumeIsolated { DebugDrawer.shared.attach(to: windowScene) }
                }
            }
        }

        // Called on the main thread by the framework's code once its window is open.
        @_cdecl("orders_window_did_open")
        public func ordersWindowDidOpen() {
            MainActor.assumeIsolated { DebugDrawerAttacher.shared.attachEveryScene() }
        }
    #endif

    #if os(tvOS)
        struct PlayPauseTriggerExample: View {
            var body: some View {
                // Play/Pause on the Siri Remote (tvOS), attached outside .debugDrawer() so it also closes it
                Text("Home")
                    .debugDrawer()
                    .onPlayPauseCommand { DebugDrawer.shared.toggle() }
            }
        }
    #endif

    #if os(macOS)
        import ViewInspector

        @MainActor
        @Suite
        struct OpeningTheDrawerExamplesTests {
            @Test("The Ctrl-D trigger is a hidden button behind the app's view")
            func shortcutTriggerIsAHiddenButton() throws {
                let sut = ShortcutTriggerExample()

                let actual = try sut.inspect().find(ViewType.Button.self)

                #expect(actual.isHidden())
            }
        }
    #endif
#endif
