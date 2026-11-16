#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// The payloads, the latest period first, one of them open to its JSON, then buttons that mark
    /// every payload seen and delete them all.
    struct MetricKitPayloadsView: View {
        let payloads: [MetricKitPayload]
        /// The payload open to its JSON, if any.
        @Binding var expanded: MetricKitPayload.ID?
        /// Called when a payload is opened: it is then seen.
        let onOpen: (MetricKitPayload.ID) -> Void
        let onDelete: (MetricKitPayload.ID) -> Void
        let onMarkAllSeen: () -> Void
        let onDeleteAll: () -> Void

        var body: some View {
            DebugDrawerSection {
                ForEach(payloads) { payload in
                    MetricKitPayloadRow(
                        payload: payload,
                        isExpanded: expanded == payload.id,
                        onToggle: { toggle(payload.id) },
                        onDelete: { onDelete(payload.id) }
                    )
                }
            } footer: {
                if payloads.isEmpty {
                    Text("No MetricKit payloads. A device delivers metrics about once a day and diagnostics as they happen; the simulator, none.")
                }
            }
            if !payloads.isEmpty {
                DebugDrawerActionRow {
                    Button("Mark All Seen", action: onMarkAllSeen)
                        .disabled(payloads.allSatisfy(\.isSeen))
                        .accessibilityHint("Clears the badge without opening each payload")
                } trailing: {
                    Button("Delete All", role: .destructive, action: onDeleteAll)
                        .debugDrawerButtonStyle(.destructive)
                        .accessibilityHint("Deletes every MetricKit payload")
                }
            }
        }

        private func toggle(_ id: MetricKitPayload.ID) {
            if expanded == id {
                expanded = nil
            } else {
                expanded = id
                onOpen(id)
            }
        }
    }
#endif
