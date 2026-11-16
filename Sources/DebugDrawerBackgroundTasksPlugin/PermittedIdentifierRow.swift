#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// One permitted identifier: whether a request for it is pending, a Schedule button for each
    /// kind the background modes allow, a refusal's reason, and a menu that copies the LLDB
    /// commands that launch or expire its task.
    struct PermittedIdentifierRow: View {
        let identifier: PermittedIdentifier
        /// The pending request for it, if any.
        let pendingRequest: BackgroundTaskRequest?
        /// The kinds it can be scheduled as.
        let kinds: [BackgroundTaskKind]
        /// The latest Schedule, as this row shows it.
        let schedule: ScheduleState
        let onSchedule: (BackgroundTaskKind) -> Void

        var body: some View {
            TaskIdentifierRow(identifier.id) {
                DebugDrawerIssueGlyph(severity)
            } details: {
                Text(status)
                if !identifier.isWildcard {
                    outcome
                    if !kinds.isEmpty {
                        scheduleButtons
                    }
                }
            } accessory: {
                if !identifier.isWildcard {
                    copyMenu
                }
            }
            .accessibilityElement(children: .contain)
        }

        /// Whether a request is pending, or what a wildcard is for.
        private var status: String {
            if identifier.isWildcard {
                "A wildcard, for continued processing tasks the app starts itself."
            } else if let pendingRequest {
                "Pending · \(pendingRequest.kind.title)"
            } else {
                "Not scheduled"
            }
        }

        /// Whether a Schedule for this identifier is on its way; a refused one can be tried again.
        private var isScheduling: Bool {
            if case .scheduling = schedule { return true }
            return false
        }

        private var severity: DebugDrawerIssueGlyph.Severity {
            if case .failed = schedule { return .error }
            return pendingRequest == nil ? .neutral : .ok
        }

        /// A Schedule on its way, or why the scheduler refused the last one.
        @ViewBuilder private var outcome: some View {
            switch schedule {
            case .idle:
                EmptyView()
            case .scheduling:
                HStack(spacing: 4) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Scheduling…")
                }
                .accessibilityElement(children: .combine)
            case let .failed(_, kind, failure):
                Label {
                    Text("\(kind.title) refused — \(failure.title). \(failure.explanation)")
                } icon: {
                    DebugDrawerIssueGlyph(.error)
                        .accessibilityHidden(true)
                }
            }
        }

        // Borderless, as links in the row: a push button per kind beside the copy commands made a
        // column of four buttons under every identifier.
        private var scheduleButtons: some View {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { scheduleButtonList }
                VStack(alignment: .leading, spacing: 4) { scheduleButtonList }
            }
            .debugDrawerButtonStyle(.borderless)
            .debugDrawerFont(.body)
        }

        private var scheduleButtonList: some View {
            ForEach(kinds, id: \.self) { kind in
                Button("Schedule \(kind.title)") { onSchedule(kind) }
                    .accessibilityLabel("Schedule \(kind.title) for \(identifier.id)")
                    .accessibilityHint("Submits a request that may begin now")
                    .disabled(isScheduling)
            }
        }

        /// The LLDB commands, which only the debugger may run, to copy and paste at its prompt.
        private var copyMenu: some View {
            Menu {
                Button("Copy Launch Command") { debugDrawerCopyToClipboard(identifier.simulateLaunchCommand) }
                    .accessibilityLabel("Copy Launch Command for \(identifier.id)")
                    .accessibilityHint("Copies the LLDB command that launches the task")
                Button("Copy Expiration Command") { debugDrawerCopyToClipboard(identifier.simulateExpirationCommand) }
                    .accessibilityLabel("Copy Expiration Command for \(identifier.id)")
                    .accessibilityHint("Copies the LLDB command that expires the running task")
            } label: {
                Label("Copy LLDB Command", systemImage: "doc.on.doc")
                    .labelStyle(.iconOnly)
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .debugDrawerButtonStyle(.borderless)
            .fixedSize()
            .accessibilityLabel("Copy an LLDB command for \(identifier.id)")
            .help("Copy the LLDB command that launches or expires this task")
        }
    }
#endif
