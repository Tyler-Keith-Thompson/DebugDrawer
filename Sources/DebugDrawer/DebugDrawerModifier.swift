#if DEBUG
    import SwiftUI

    // MARK: - Root modifier (attach once at app level)

    struct DebugDrawerModifier: ViewModifier {
        @ObservedObject var drawer = DebugDrawer.shared
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        func body(content: Content) -> some View {
            content
                // Under the drawer, which takes no touches while closed, so the HUD keeps working.
                .overlay {
                    let readouts = drawer.hudPlugins
                    if !readouts.isEmpty {
                        DrawerHUDView(
                            readouts: readouts,
                            origin: drawer.hudLayout.origin,
                            move: { drawer.moveHUD(to: $0) },
                            unpin: { drawer.toggleHUD(forPlugin: $0) }
                        )
                        .opacity(drawer.isHUDHidden ? 0 : 1)
                    }
                }
                .overlay(alignment: .trailing) {
                    DebugDrawerOverlay(drawer: drawer)
                        .accessibilityIdentifier(debugDrawerOverlayIdentifier)
                        .background(DebugDrawerTagView())
                        .allowsHitTesting(drawer.isOpen)
                }
                .overlay(alignment: .topTrailing) {
                    // A toast exists only while the drawer is closed; opening it is the toast's job.
                    if !drawer.isOpen, let toast = drawer.toast {
                        DrawerToastView(
                            toast: toast,
                            plugin: (drawer.localPlugins + drawer.globalPlugins).first { $0.id == toast.pluginID },
                            open: { drawer.openToast() },
                            dismiss: { drawer.dismissToast() }
                        )
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: drawer.isOpen)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: drawer.toast)
        }
    }

    // MARK: - Platform view tagger

    /// Tags the nearest platform view with a known tag so the a11y auditor
    /// can skip the debug drawer subtree without relying on class names.
    public let debugDrawerViewTag = 0xDDB6 // "DDB" = DebugDrawerBoundary

    #if os(macOS)
        struct DebugDrawerTagView: NSViewRepresentable {
            func makeNSView(context _: Context) -> NSView {
                let view = NSView()
                view.setAccessibilityIdentifier(debugDrawerOverlayIdentifier)
                return view
            }

            func updateNSView(_: NSView, context _: Context) {}
        }
    #elseif os(iOS)
        struct DebugDrawerTagView: UIViewRepresentable {
            func makeUIView(context _: Context) -> UIView {
                let view = UIView()
                view.tag = debugDrawerViewTag
                view.accessibilityIdentifier = debugDrawerOverlayIdentifier
                return view
            }

            func updateUIView(_: UIView, context _: Context) {}
        }
    #endif

    // MARK: - Local plugin modifier

    /// Attaches a local plugin to this view's lifecycle.
    /// The plugin appears in the drawer when this view is on screen
    /// and is removed when the view disappears — but only if no newer
    /// view has already replaced the registration.
    ///
    /// Re-registers automatically when the plugin's `contentIdentifier` changes,
    /// so this works regardless of where `.id()` is placed in the chain.
    struct LocalPluginModifier<P: DebugDrawerPlugin>: ViewModifier {
        let plugin: P
        @State private var token: UUID?

        func body(content: Content) -> some View {
            content
                .onAppear {
                    token = DebugDrawer.shared.registerLocal(plugin)
                }
                .onDisappear {
                    if let token {
                        DebugDrawer.shared.unregisterLocal(id: plugin.id, token: token)
                    }
                }
                .onChange(of: plugin.contentIdentifier) { _, _ in
                    token = DebugDrawer.shared.registerLocal(plugin)
                }
        }
    }

    // MARK: - Public API

    public extension View {
        /// Attaches the debug drawer overlay to this view.
        /// Place once at the root of your view hierarchy. While the drawer is open, Cmd-K focuses its
        /// search field, which finds plugins and their ``DebugDrawerPlugin/actions``; Cmd-Option-Down
        /// and Cmd-Option-Up move to the next and previous plugin; Escape clears the search, then
        /// closes the drawer. Opening it is the app's job: call ``DebugDrawer/toggle()``.
        func debugDrawer() -> some View {
            modifier(DebugDrawerModifier())
        }

        /// Registers a local debug plugin that is active while this view is on screen.
        func debugLocalPlugin<P: DebugDrawerPlugin>(_ plugin: P) -> some View {
            modifier(LocalPluginModifier(plugin: plugin))
        }
    }
#else
    import SwiftUI

    public extension View {
        func debugDrawer() -> some View {
            self
        }

        func debugLocalPlugin<P: DebugDrawerPlugin>(_: P) -> some View {
            self
        }
    }
#endif
