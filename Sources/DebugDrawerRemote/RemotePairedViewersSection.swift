#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// The viewers paired, oldest first, each with Disconnect.
    struct RemotePairedViewersSection: View {
        let viewers: [DebugDrawerPairedViewer]
        let disconnect: (DebugDrawerPairedViewer) -> Void

        var body: some View {
            DebugDrawerSection("Paired viewers") {
                ForEach(viewers) { viewer in
                    DebugDrawerRow(viewer.name, systemImage: "laptopcomputer") {
                        Button("Disconnect", role: .destructive) { disconnect(viewer) }
                            .debugDrawerButtonStyle(.destructive)
                            .accessibilityLabel("Disconnect \(viewer.name)")
                            .help("End this viewer's connection; it must pair again")
                    }
                }
            } footer: {
                if viewers.isEmpty {
                    Text("No viewer is paired.")
                }
            }
        }
    }
#endif
