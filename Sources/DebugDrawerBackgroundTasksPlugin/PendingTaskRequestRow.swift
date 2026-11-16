#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// One pending request: its identifier, its kind and the conditions it waits for, its earliest
    /// begin date, and a button that cancels it.
    struct PendingTaskRequestRow: View {
        let request: BackgroundTaskRequest
        let onCancel: () -> Void
        @Environment(\.locale) private var locale
        @Environment(\.timeZone) private var timeZone

        var body: some View {
            TaskIdentifierRow(request.id) {
                Image(systemName: request.kind.systemImage)
                    .debugDrawerFont(.body)
                    .debugDrawerForegroundStyle(.secondary)
                    .accessibilityHidden(true)
            } details: {
                Text(request.kind.summary)
                earliestBegin
            } accessory: {
                Button(role: .destructive, action: onCancel) {
                    Label("Cancel", systemImage: "xmark.circle")
                        .labelStyle(.iconOnly)
                }
                .debugDrawerButtonStyle(.borderless)
                .accessibilityLabel("Cancel \(request.id)")
                .help("Cancel this request")
            }
            .accessibilityElement(children: .contain)
        }

        /// The date as a value beside its label, or that there is none.
        @ViewBuilder private var earliestBegin: some View {
            if let date = request.earliestBeginDate {
                // Beside its label where both fit, below it otherwise, so the date never wraps.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("Earliest begin")
                        Text(formatted(date))
                            .debugDrawerFont(.value)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Earliest begin")
                        Text(formatted(date))
                            .debugDrawerFont(.value)
                    }
                }
                .accessibilityElement(children: .combine)
            } else {
                Text("No earliest begin date: as soon as the system allows")
            }
        }

        private func formatted(_ date: Date) -> String {
            var style = Date.FormatStyle(date: .abbreviated, time: .standard, locale: locale)
            style.timeZone = timeZone
            return date.formatted(style)
        }
    }
#endif
