#if DEBUG
    import SwiftUI

    // MARK: - Root modifier (attach once at app level)

    // The modifier applies no animation to the app's content: each layer it adds animates itself
    // (the HUD's fade, the toast's slide, the panel's transition in its own window), so a change
    // to the drawer never animates a change of the app's.
    struct DebugDrawerModifier: ViewModifier {
        @ObservedObject var drawer = DebugDrawer.shared

        func body(content: Content) -> some View {
            content
                // The chrome boundary's first layer: the HUD, the panel and the toast come after it
                // (DrawerChromeBoundary).
                .overlay { DrawerChromeBoundaryMarker(layerName: debugDrawerChromeStartLayerName) }
                // Under the drawer, which takes no touches while closed, so the HUD keeps working.
                .overlay { DrawerHUDLayer(drawer: drawer) }
                .drawerPresentation(drawer: drawer)
                .overlay(alignment: .topTrailing) { DrawerToastLayer(drawer: drawer) }
                .overlay { DrawerChromeBoundaryMarker(layerName: debugDrawerChromeEndLayerName) }
        }
    }

    /// The pinned plugins' HUD, if any are pinned, faded out while a capture hides it.
    private struct DrawerHUDLayer: View {
        @ObservedObject var drawer: DebugDrawer

        var body: some View {
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
    }

    /// The toast, sliding in from the top, while the key window's drawer is closed: opening the
    /// drawer is the toast's job.
    private struct DrawerToastLayer: View {
        @ObservedObject var drawer: DebugDrawer
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            ZStack {
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
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: drawer.toast)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: drawer.isOpen)
        }
    }

    // MARK: - Presentation

    extension View {
        /// Places the drawer: on the Mac and iOS in a window of its own, attached to the window
        /// this view is in; on visionOS in an ornament beside the window; on tvOS in an overlay
        /// along the window's trailing edge; and on watchOS a full-screen list of the plugins.
        @ViewBuilder
        fileprivate func drawerPresentation(drawer: DebugDrawer) -> some View {
            #if os(watchOS)
                // A watch has no room beside the app, so the drawer covers it, as a navigation
                // list (DrawerWatchList). Its Close button closes the drawer, and a dismissal by the
                // system closes it too (isOpenBinding).
                fullScreenCover(isPresented: drawer.isOpenBinding) {
                    DrawerWatchList(drawer: drawer, presentation: drawer.detachedPresentation)
                        .accessibilityIdentifier(debugDrawerOverlayIdentifier)
                }
            #elseif os(macOS) || os(iOS)
                // A window of the drawer's own (DrawerChildPanel, DrawerSceneWindow), so sheets and
                // alerts the app presents stay under it. Mac Catalyst takes this branch: its scenes
                // are UIKit's, and the drawer's window draws over the scene's others there too.
                background { DrawerWindowAttacher(drawer: drawer) }
            #elseif os(visionOS)
                // An ornament, not a separate window: it needs no scene from the host (a window
                // would need a WindowGroup the app declares and an openWindow call), it moves
                // with the app's window and stays beside it instead of floating wherever the
                // system puts a new window, and it covers none of the app, which an overlay on a
                // spatial window would. It takes the window's height, so the plugin list scrolls
                // as it does in the overlay.
                modifier(DrawerOrnament(
                    isOpen: drawer.detachedPresentation.isOpen,
                    panel: DebugDrawerOverlay(drawer: drawer, presentation: drawer.detachedPresentation)
                        .accessibilityIdentifier(debugDrawerOverlayIdentifier)
                ))
            #else
                // tvOS keeps the overlay in the app's window: the focus engine moves within one
                // window's views, so a window of the drawer's own would take focus from the app
                // whenever it showed. So on tvOS a sheet or an alert the app presents still covers
                // the drawer.
                overlay(alignment: .trailing) {
                    DebugDrawerOverlay(drawer: drawer, presentation: drawer.detachedPresentation)
                        .accessibilityIdentifier(debugDrawerOverlayIdentifier)
                        .allowsHitTesting(drawer.isOpen)
                }
            #endif
        }
    }

    #if os(watchOS)
        extension DebugDrawer {
            /// Whether the drawer is open, for a presentation the system can also dismiss: the
            /// system's dismissal closes the drawer through ``toggle()``.
            fileprivate var isOpenBinding: Binding<Bool> {
                Binding(
                    get: { self.isOpen },
                    set: { isPresented in
                        if isPresented != self.isOpen { self.toggle() }
                    }
                )
            }
        }
    #endif

    #if os(visionOS)
        /// The drawer's panel in an ornament on the window's trailing edge, as tall as the window.
        private struct DrawerOrnament<Panel: View>: ViewModifier {
            let isOpen: Bool
            let panel: Panel
            @State private var windowHeight: CGFloat?

            func body(content: Content) -> some View {
                content
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { windowHeight = $0 }
                    .ornament(visibility: isOpen ? .visible : .hidden, attachmentAnchor: .scene(.trailing), contentAlignment: .leading) {
                        panel.frame(height: windowHeight)
                    }
            }
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
        /// Attaches the debug drawer to this view.
        ///
        /// Place it once, at the root of the app's view hierarchy. While the drawer is open, Cmd-K
        /// focuses its search field, which finds plugins and their ``DebugDrawerPlugin/actions``;
        /// Cmd-Option-Down and Cmd-Option-Up move to the next and previous plugin; Escape clears the
        /// search, then closes the drawer. Opening it is the app's job: call
        /// ``DebugDrawer/toggle()``.
        ///
        /// In release builds it returns the view unchanged.
        ///
        /// - Returns: The view with the drawer, its HUD and its toasts over it.
        func debugDrawer() -> some View {
            modifier(DebugDrawerModifier())
        }

        /// Adds `plugin` to the drawer while this view is on screen.
        ///
        /// The plugin is registered when the view appears, registered again when its
        /// ``DebugDrawerPlugin/contentIdentifier`` changes, and removed when the view disappears,
        /// unless a newer view has registered a plugin with the same ID since. In release builds it
        /// returns the view unchanged.
        ///
        /// - Parameter plugin: The plugin to show.
        /// - Returns: The view, unchanged in how it looks.
        func debugLocalPlugin<P: DebugDrawerPlugin>(_ plugin: P) -> some View {
            modifier(LocalPluginModifier(plugin: plugin))
        }
    }
#else
    import SwiftUI

    // The release stand-ins: the same signatures, so the host's code compiles unchanged, and no
    // drawer behind them.
    public extension View {
        /// Returns the view unchanged: release builds have no drawer.
        ///
        /// - Returns: This view.
        func debugDrawer() -> some View {
            self
        }

        /// Returns the view unchanged: release builds have no drawer, so the plugin is never read.
        ///
        /// - Parameter plugin: Ignored.
        /// - Returns: This view.
        func debugLocalPlugin<P: DebugDrawerPlugin>(_: P) -> some View {
            self
        }
    }
#endif
