#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// A request's links by replay, in its detail: "Replay of" its original's method, path and
    /// time, for a replay; "Replayed" and how often, for a request that was resent. Each has a
    /// Show button that selects the other request.
    struct NetworkReplayLinkRows: View {
        let entry: NetworkEntry
        let links: NetworkReplayLinks
        /// Selects the request with the id; `nil` offers no Show buttons.
        let onShow: ((NetworkEntry.ID) -> Void)?
        @Environment(\.locale) private var locale
        @Environment(\.timeZone) private var timeZone
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        var body: some View {
            if entry.replayOf != nil {
                if let original = links.original {
                    link("Replay of", value: summary(of: original), show: original.id, hint: "Selects the request this one resent")
                } else {
                    DebugDrawerKeyValueRow("Replay of", value: "A request no longer in the log")
                        .debugDrawerValueStyle(.text)
                }
            }
            if let latest = links.replays.first {
                let count = links.replays.count
                link("Replayed", value: count == 1 ? "Once" : "\(count) times", show: latest, hint: "Selects the latest replay of this request")
            }
        }

        /// A row with its value and, when the detail can select, a Show button at the trailing
        /// edge; at accessibility text sizes, where beside the value it would squeeze it to a word a
        /// line, below the value.
        private func link(_ label: String, value: String, show id: NetworkEntry.ID, hint: String) -> some View {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
            return layout {
                DebugDrawerKeyValueRow(label, value: value)
                    .debugDrawerValueStyle(.text)
                if let onShow {
                    Button("Show") { onShow(id) }
                        .debugDrawerButtonStyle(.borderless)
                        .accessibilityLabel(label == "Replay of" ? "Show the original request" : "Show the latest replay")
                        .accessibilityHint(hint)
                }
            }
        }

        /// The original's method, path and the time it started: "GET /v1/greeting at 10:42:05".
        private func summary(of original: NetworkEntry) -> String {
            let time = original.timestamp.formatted(Date.FormatStyle(date: .omitted, time: .standard, locale: locale, timeZone: timeZone))
            return "\(original.method) \(original.path) at \(time)"
        }
    }

    /// A resend that hasn't got its answer: in progress, or why it failed. Nothing once it has.
    struct NetworkReplayStatusRow: View {
        let status: NetworkReplayStatus?

        var body: some View {
            switch status {
            case .none:
                EmptyView()
            case .sending:
                DebugDrawerRow("Resending…") {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Resending")
                }
            case let .failed(message):
                DebugDrawerIssueRow("Resend failed", severity: .error) {
                    Text(message)
                }
            }
        }
    }
#endif
