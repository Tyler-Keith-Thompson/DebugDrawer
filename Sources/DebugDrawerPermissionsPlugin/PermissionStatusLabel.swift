#if DEBUG
    import SwiftUI

    /// A status as a symbol and its name, colored by how far it lets the app go. The symbol
    /// differs per grant, so the color is never all that tells them apart.
    struct PermissionStatusLabel: View {
        let status: PermissionStatus

        var body: some View {
            Label(status.title, systemImage: status.grant.symbol)
                .font(.caption.weight(.medium))
                .foregroundStyle(status.grant.color)
                .accessibilityLabel(status.title)
        }
    }

    extension PermissionStatus.Grant {
        fileprivate var color: Color {
            switch self {
            case .granted: .green
            case .partial: .orange
            case .refused: .red
            case .undecided: .blue
            case .unknown: .secondary
            }
        }
    }
#endif
