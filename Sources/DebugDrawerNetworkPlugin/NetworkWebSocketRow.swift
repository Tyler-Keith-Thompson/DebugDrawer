#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// A WebSocket connection in the log: "WS", whether it is open, closed or failed, its path and
    /// how many frames it carried, after an error glyph when it failed; selected, it shows the
    /// connection's detail and frames.
    struct NetworkWebSocketRow: View {
        let connection: NetworkWebSocketConnection
        let redaction: DebugDrawerRedaction
        let isSelected: Bool
        let onSelect: () -> Void
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                Button(action: onSelect) {
                    // At accessibility text sizes the path and the frame count have no room beside
                    // the method and state, so each takes a line of its own, as a request's do.
                    let layout = dynamicTypeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: 1))
                        : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
                    layout {
                        HStack(alignment: .firstTextBaseline) {
                            glyph
                            Text("WS")
                                .debugDrawerFont(.code)
                                .debugDrawerForegroundStyle(.secondary)
                                .accessibilityLabel("WS, WebSocket")
                            Text(connection.stateLabel)
                                .debugDrawerFont(.value)
                                .debugDrawerForegroundStyle(connection.isFailure ? .error : connection.isOpen ? .accent : .primary)
                        }
                        // A few short words that never wrap: the path gives way to them instead.
                        .fixedSize(horizontal: true, vertical: false)
                        Text(connection.path)
                            .debugDrawerFont(.code)
                            .debugDrawerForegroundStyle(.primary)
                            .lineLimit(3)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(connection.frameCountLabel)
                            .debugDrawerFont(.value)
                            .debugDrawerForegroundStyle(.tertiary)
                    }
                    .debugDrawerRowPadding()
                    .contentShape(Rectangle())
                }
                .debugDrawerButtonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])

                if isSelected {
                    NetworkWebSocketDetail(connection: connection, redaction: redaction)
                }
            }
        }

        /// The error glyph for a failed connection; for any other, the same space left empty, so
        /// the method lines up with the requests' above.
        private var glyph: some View {
            DebugDrawerIssueGlyph(.error)
                .opacity(connection.isFailure ? 1 : 0)
                .accessibilityHidden(!connection.isFailure)
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - $0.height * 0.15 }
        }
    }

    extension NetworkWebSocketConnection {
        /// "Open", "Closed" or "Failed".
        var stateLabel: String {
            switch state {
            case .open: "Open"
            case .closed: "Closed"
            case .failed: "Failed"
            }
        }

        /// "No frames", "1 frame", "12 frames".
        var frameCountLabel: String {
            switch frameCount {
            case 0: "No frames"
            case 1: "1 frame"
            default: "\(frameCount.formatted()) frames"
            }
        }
    }
#endif
