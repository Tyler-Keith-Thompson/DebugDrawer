#if DEBUG
    import SwiftUI

    /// The floating HUD: the pinned plugins' readouts on one card, which the developer drags
    /// anywhere in the window. Only the card takes touches; the rest of the window reaches the app.
    struct DrawerHUDView: View {
        /// The pinned plugins, each with a HUD readout, in the order they are listed.
        let readouts: [AnyDebugDrawerPlugin]
        /// The card's top-leading corner, or `nil` for the default corner.
        let origin: CGPoint?
        /// Called with the card's new corner when a drag ends.
        let move: (CGPoint) -> Void
        /// Called with a plugin's ID when the developer removes its readout.
        let unpin: (String) -> Void

        @State private var drag = CGSize.zero
        @State private var cardSize = CGSize.zero

        var body: some View {
            // GeometryReader draws nothing of its own, so it takes no touches outside the card.
            GeometryReader { container in
                let corner = (origin ?? Self.defaultOrigin).kept(showing: cardSize, in: container.size)
                card
                    .onGeometryChange(for: CGSize.self, of: \.size) { cardSize = $0 }
                    .offset(x: corner.x + drag.width, y: corner.y + drag.height)
                // tvOS has no drag gesture, so there the card stays at its corner.
                #if !os(tvOS)
                    .gesture(
                        DragGesture()
                            .onChanged { drag = $0.translation }
                            .onEnded { value in
                                drag = .zero
                                let end = CGPoint(x: corner.x + value.translation.width, y: corner.y + value.translation.height)
                                move(end.kept(showing: cardSize, in: container.size))
                            }
                    )
                #endif
            }
        }

        private var card: some View {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(readouts) { plugin in
                    // watchOS deprecates context menus, so there a readout leaves the HUD only
                    // through DebugDrawer.toggleHUD(forPlugin:).
                    #if os(watchOS)
                        plugin.hud
                    #else
                        plugin.hud
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

        /// Where the card sits until it is first moved: the top-leading corner, inset.
        static let defaultOrigin = CGPoint(x: 12, y: 12)
    }

    extension CGPoint {
        /// This corner moved, if need be, so a card of `size` stays inside `container`.
        fileprivate func kept(showing size: CGSize, in container: CGSize) -> CGPoint {
            CGPoint(
                x: min(max(x, 0), max(container.width - size.width, 0)),
                y: min(max(y, 0), max(container.height - size.height, 0))
            )
        }
    }
#endif
