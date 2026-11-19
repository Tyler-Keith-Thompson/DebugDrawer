#if DEBUG
    import SwiftUI

    /// The HUD's card: the pinned plugins' readouts, each with a context menu that removes it.
    ///
    /// `DrawerHUDView` places it in the window and drags it there; on the Mac it fills a panel of
    /// its own (DrawerChromePanel), which moves as it is dragged.
    struct DrawerHUDCard: View {
        /// The pinned plugins, each with a HUD readout, in the order they are listed.
        let readouts: [AnyDebugDrawerPlugin]
        /// Called with a plugin's ID when the developer removes its readout.
        let unpin: (String) -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(readouts) { plugin in
                    // watchOS deprecates context menus, so there a readout leaves the HUD only
                    // through DebugDrawer.toggleHUD(forPlugin:).
                    #if os(watchOS)
                        plugin.hud
                            .reportsVisibility(ofPlugin: plugin.id)
                    #else
                        plugin.hud
                            .reportsVisibility(ofPlugin: plugin.id)
                            .contextMenu {
                                Button("Remove \(plugin.title) from HUD") { unpin(plugin.id) }
                            }
                    #endif
                }
            }
            .padding(8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            .shadow(color: .black.opacity(0.2), radius: 4, y: 1)
            .fixedSize()
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Debug HUD")
        }
    }
#endif
