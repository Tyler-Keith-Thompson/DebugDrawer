#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// The permitted identifiers, the pending requests, and how to launch a task from the
    /// debugger, one section each.
    struct BackgroundTasksView: View {
        let declaration: BackgroundTaskDeclaration
        let pending: PendingRequestsState
        let schedule: ScheduleState
        let actions: BackgroundTasksActions

        var body: some View {
            // Sections pad themselves, so they stack with no spacing.
            VStack(alignment: .leading, spacing: 0) {
                switch pending {
                case .loading:
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Reading the pending requests…")
                            .debugDrawerFont(.secondary)
                            .debugDrawerForegroundStyle(.secondary)
                    }
                    .padding(.top, 8)
                    .accessibilityElement(children: .combine)
                case let .loaded(requests):
                    PermittedIdentifiersSection(declaration: declaration, pending: requests, schedule: schedule, onSchedule: actions.schedule)
                    PendingRequestsSection(
                        requests: requests,
                        onCancel: actions.cancel,
                        onCancelAll: actions.cancelAll,
                        onRefresh: actions.refresh
                    )
                }
                DebugDrawerSection("Simulating a Launch") {
                    EmptyView()
                } footer: {
                    Text(Self.simulatingALaunch)
                }
            }
        }

        /// How to use the copied commands, which call private API that only the debugger may.
        static let simulatingALaunch = """
        Schedule a request and copy its launch command with the copy button beside the identifier. \
        Pause the app in Xcode (Debug ▸ Pause), paste the command at the (lldb) prompt and \
        continue: the system runs the task's launch handler at once. The expiration command, \
        pasted while the task runs, calls its expiration handler. On a device only: the simulator \
        runs no background tasks.
        """
    }
#endif
