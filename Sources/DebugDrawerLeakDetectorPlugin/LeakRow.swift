#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// One suspect: its class, how many are alive and why that's wrong, when it was flagged, and a
    /// button that ignores the class.
    struct LeakRow: View {
        let suspect: LeakSuspect
        let onIgnore: () -> Void
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize
        @Environment(\.locale) private var locale
        @Environment(\.timeZone) private var timeZone

        var body: some View {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
            layout {
                VStack(alignment: .leading, spacing: 2) {
                    Text(suspect.type.name)
                        .font(.system(.caption, design: .monospaced).weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(suspect.summary)
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(facts)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                Button("Ignore", action: onIgnore)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityLabel("Ignore \(suspect.type.name)")
                    .accessibilityHint("Stops showing and counting this class's suspects")
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
        }

        /// What kind of suspect, and since when.
        private var facts: String {
            let date = suspect.since.formatted(Date.FormatStyle(date: .abbreviated, time: .standard, locale: locale, timeZone: timeZone))
            return "\(suspect.reason.title) · flagged \(date)"
        }
    }

    extension LeakSuspect.Reason {
        /// What kind of object the suspect is, as the drawer names it.
        fileprivate var title: String {
            switch self {
            case .aliveAfterDismissal: "View controller"
            case .overLimit: "Tracked object"
            }
        }
    }
#endif
