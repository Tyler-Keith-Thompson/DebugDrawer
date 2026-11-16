#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// One permission: its name and status, the usage descriptions that declare it, what the
    /// status means where it needs saying, and its buttons.
    struct PermissionRow: View {
        let row: PermissionRowState
        let onRequest: () -> Void
        let onOpenSettings: () -> Void
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize
        @ScaledMetric(relativeTo: .caption) private var iconWidth: CGFloat = 18

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: row.permission.kind.icon)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: iconWidth)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        titleLine
                        details
                    }
                }
                .accessibilityElement(children: .combine)
                buttons
                    .padding(.leading, iconWidth + 6)
            }
            .padding(.vertical, 2)
        }

        /// The name and the status: side by side, or one above the other at accessibility text
        /// sizes.
        private var titleLine: some View {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 6))
            return layout {
                Text(row.permission.kind.title)
                    .font(.caption.weight(.semibold))
                if !dynamicTypeSize.isAccessibilitySize {
                    Spacer(minLength: 4)
                }
                PermissionStatusLabel(status: row.status)
            }
        }

        @ViewBuilder private var details: some View {
            if row.permission.usageDescriptions.isEmpty {
                Text("Needs no usage description.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            ForEach(row.permission.usageDescriptions, id: \.key) { description in
                VStack(alignment: .leading, spacing: 0) {
                    Text(description.text)
                        .font(.caption)
                    Text(description.key)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            if let explanation = row.status.explanation {
                Text(explanation)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if case let .needsKey(key) = row.request {
                Text("Asking needs \(key) in the Info.plist.")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        /// Request, while it can be asked for, and Open Settings: side by side, or one above the
        /// other at accessibility text sizes.
        private var buttons: some View {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                : AnyLayout(HStackLayout())
            return layout {
                switch row.request {
                case .available:
                    Button("Request", action: onRequest)
                        .accessibilityLabel("Request \(row.permission.kind.title) access")
                        .accessibilityHint("Shows the system's prompt")
                case .inProgress:
                    HStack(spacing: 4) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Asking…")
                            .font(.caption)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Asking for \(row.permission.kind.title) access")
                case .needsKey, .unavailable:
                    EmptyView()
                }
                Button("Open Settings", action: onOpenSettings)
                    .accessibilityLabel("Open Settings for \(row.permission.kind.title)")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
#endif
