#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// The WebSockets section, below the request log: each connection the app opened that the
    /// filters pass, the latest first. Nothing shows while there are none.
    struct NetworkWebSocketsSection: View {
        let connections: [NetworkWebSocketConnection]
        let redaction: DebugDrawerRedaction
        /// The connection whose detail shows, if any.
        @Binding var selected: NetworkWebSocketConnection.ID?

        var body: some View {
            if !connections.isEmpty {
                DebugDrawerSection("WebSockets") {
                    ForEach(connections) { connection in
                        let isSelected = selected == connection.id
                        NetworkWebSocketRow(
                            connection: connection,
                            redaction: redaction,
                            isSelected: isSelected,
                            onSelect: { selected = isSelected ? nil : connection.id }
                        )
                    }
                }
            }
        }
    }
#endif
