#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// The requests waiting in the scheduler, each cancellable, with Refresh and Cancel All.
    struct PendingRequestsSection: View {
        let requests: [BackgroundTaskRequest]
        let onCancel: (BackgroundTaskRequest.ID) -> Void
        let onCancelAll: () -> Void
        let onRefresh: () -> Void

        var body: some View {
            DebugDrawerSection("Pending Requests (\(requests.count))") {
                ForEach(requests) { request in
                    PendingTaskRequestRow(request: request) {
                        onCancel(request.id)
                    }
                }
                DebugDrawerActionRow {
                    Button("Refresh", action: onRefresh)
                        .accessibilityLabel("Refresh pending requests")
                } trailing: {
                    if !requests.isEmpty {
                        Button("Cancel All", role: .destructive, action: onCancelAll)
                            .debugDrawerButtonStyle(.destructive)
                            .accessibilityLabel("Cancel all pending requests")
                    }
                }
            } footer: {
                if requests.isEmpty {
                    Text("No pending requests.")
                }
            }
        }
    }
#endif
