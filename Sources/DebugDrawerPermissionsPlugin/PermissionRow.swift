#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// One permission as an issue row: its glyph and name with its status ("Camera — Denied"), the
    /// key of the usage description that declares it, its text, what the status means where it
    /// needs saying, and its buttons.
    struct PermissionRow: View {
        let row: PermissionRowState
        let onRequest: () -> Void
        let onOpenSettings: () -> Void

        var body: some View {
            DebugDrawerIssueRow(
                row.permission.kind.title,
                status: row.status.title,
                severity: row.status.grant.severity,
                subline: row.permission.usageDescriptions.first?.key
            ) {
                details
            }
        }

        @ViewBuilder private var details: some View {
            if row.permission.usageDescriptions.isEmpty {
                Text("Needs no usage description.")
            }
            ForEach(Array(row.permission.usageDescriptions.enumerated()), id: \.element.key) { index, description in
                // The first key is the row's subline; any others follow their own text.
                if index > 0 {
                    DebugDrawerCodeText(description.key)
                }
                Text(description.text)
            }
            if let explanation = row.status.explanation {
                Text(explanation)
            }
            if case let .needsKey(key) = row.request {
                Label {
                    Text("Asking needs \(key) in the Info.plist.")
                } icon: {
                    DebugDrawerIssueGlyph(.warning)
                        .accessibilityHidden(true)
                }
            }
            DebugDrawerActionRow {
                switch row.request {
                case .available:
                    Button("Request", action: onRequest)
                        .debugDrawerButtonStyle(.primary)
                        .accessibilityLabel("Request \(row.permission.kind.title) access")
                        .accessibilityHint("Shows the system's prompt")
                case .inProgress:
                    HStack(spacing: 4) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Asking…")
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Asking for \(row.permission.kind.title) access")
                case .needsKey, .unavailable:
                    EmptyView()
                }
                Button("Open Settings", action: onOpenSettings)
                    .debugDrawerButtonStyle(row.request.isOffered ? .borderless : .secondary)
                    .accessibilityLabel("Open Settings for \(row.permission.kind.title)")
            }
        }
    }

    extension PermissionRequest {
        /// Whether the row offers Request (or is asking): Open Settings then steps back to a
        /// borderless link beside the primary button, so a column of undecided rows isn't a wall
        /// of push buttons.
        fileprivate var isOffered: Bool {
            switch self {
            case .available, .inProgress: true
            case .needsKey, .unavailable: false
            }
        }
    }

    extension PermissionStatus.Grant {
        /// The issue glyph for how far a status lets the app go.
        fileprivate var severity: DebugDrawerIssueGlyph.Severity {
            switch self {
            case .granted: .ok
            case .partial: .warning
            case .refused: .error
            case .undecided, .unknown: .neutral
            }
        }
    }
#endif
