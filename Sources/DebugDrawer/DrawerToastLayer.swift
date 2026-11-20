#if DEBUG
    import SwiftUI

    /// The toast, sliding in from the top, while the key window's drawer is closed: opening the
    /// drawer is the toast's job.
    ///
    /// On iOS it is drawn in a window of the drawer's own (DrawerChromeWindow), and on tvOS,
    /// visionOS and watchOS by `debugDrawer()` over the app's view. The Mac draws it in a panel of
    /// its own just the toast's size (DrawerChromePanel), so there it fades: a slide would be
    /// clipped at the panel's edge.
    struct DrawerToastLayer: View {
        @ObservedObject var drawer: DebugDrawer
        /// Called with the toast's frame, in global coordinates and without its margin, and with
        /// `nil` once it has gone.
        var toastFrameDidChange: (CGRect?) -> Void = { _ in }
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @AccessibilityFocusState private var focusedButton: DrawerToastView.FocusedButton?

        var body: some View {
            ZStack {
                if !drawer.isOpen, let toast = drawer.toast {
                    DrawerToastView(
                        toast: toast,
                        plugin: (drawer.localPlugins + drawer.globalPlugins).first { $0.id == toast.pluginID },
                        open: { drawer.openToast() },
                        dismiss: { drawer.dismissToast() },
                        hold: { drawer.setToastHeld($1, by: $0) },
                        focusedButton: $focusedButton
                    )
                    .onGeometryChange(for: CGRect.self) { proxy in
                        proxy.frame(in: .global).insetBy(dx: DrawerToastView.margin, dy: DrawerToastView.margin)
                    } action: { toastFrameDidChange($0) }
                    .onDisappear {
                        toastFrameDidChange(nil)
                        drawer.setToastHeld(false, by: .accessibilityFocus)
                    }
                    #if os(macOS)
                        .transition(.opacity)
                    #else
                        .transition(.move(edge: .top).combined(with: .opacity))
                    #endif
                }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: drawer.toast)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: drawer.isOpen)
            // VoiceOver reading the toast holds it: it shouldn't leave mid-sentence.
            .onChange(of: focusedButton) { _, focused in drawer.setToastHeld(focused != nil, by: .accessibilityFocus) }
        }
    }
#endif
