#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// Every identifier the Info.plist permits, each with its Schedule buttons and LLDB commands,
    /// and a warning when the background modes allow no kind of request.
    struct PermittedIdentifiersSection: View {
        let declaration: BackgroundTaskDeclaration
        let pending: [BackgroundTaskRequest]
        let schedule: ScheduleState
        let onSchedule: (String, BackgroundTaskKind) -> Void

        var body: some View {
            DebugDrawerSection("Permitted Identifiers (\(declaration.identifiers.count))") {
                ForEach(declaration.identifiers) { identifier in
                    PermittedIdentifierRow(
                        identifier: identifier,
                        pendingRequest: pending.first { $0.id == identifier.id },
                        kinds: declaration.kinds,
                        schedule: schedule.shown(for: identifier.id)
                    ) { kind in
                        onSchedule(identifier.id, kind)
                    }
                }
            } footer: {
                if declaration.identifiers.isEmpty {
                    Text("The Info.plist lists no \(BackgroundTaskDeclaration.permittedIdentifiersKey).")
                } else if declaration.kinds.isEmpty {
                    Label {
                        Text("\(BackgroundTaskDeclaration.backgroundModesKey) lists neither fetch nor processing, so the system runs no request.")
                    } icon: {
                        DebugDrawerIssueGlyph(.warning)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
    }
#endif
