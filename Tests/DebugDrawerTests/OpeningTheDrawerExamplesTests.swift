// The triggers of InstallingInSwiftUI.md's "Open the drawer" example, each placed in a view or a
// window so it compiles as written there.

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
