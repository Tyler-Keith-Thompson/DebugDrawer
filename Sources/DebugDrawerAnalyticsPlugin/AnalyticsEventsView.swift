#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// The events, the newest first, in a scrolling list under a filter field; below it the
    /// selected event's properties and JSON at the drawer's full width, then Export All and Clear.
    /// With no events it says how they arrive.
    struct AnalyticsEventsView: View {
        let events: [AnalyticsEvent]
        /// How many events the log keeps, which the list notes once it holds that many.
        let capacity: Int
        /// What the filter field holds.
        @Binding var query: String
        /// The selected event, whose properties show below the list, if any.
        @Binding var selected: AnalyticsEvent.ID?
        let redaction: DebugDrawerRedaction
        let onClear: () -> Void
        /// The tallest the list grows before it scrolls.
        @ScaledMetric(relativeTo: .body) private var listHeight: CGFloat = 360

        var body: some View {
            if events.isEmpty {
                DebugDrawerSection {
                    EmptyView()
                } footer: {
                    Text("No events yet. Each one the app passes to AnalyticsEvents.record shows here as it is sent.")
                }
            } else {
                list
            }
        }

        private var list: some View {
            let matching = events.filter { $0.matches(query) }
            return VStack(alignment: .leading, spacing: 0) {
                DebugDrawerSearchableList(
                    "Filter events…",
                    text: $query,
                    accessibilityLabel: "Filter events by name, property or value",
                    maxHeight: listHeight
                ) {
                    ForEach(matching) { event in
                        AnalyticsEventRow(
                            event: event,
                            isSelected: selected == event.id,
                            onToggle: { selected = selected == event.id ? nil : event.id }
                        )
                    }
                }
                // Below the list rather than inside it, so the JSON shows at its natural height
                // instead of scrolling in a box that itself scrolls. Only while the filter still
                // lists it, so the detail never names an event the list hides.
                if let event = matching.first(where: { $0.id == selected }) {
                    AnalyticsEventDetail(event: event, redaction: redaction) { selected = nil }
                }
                if let note = note(matching: matching.count) {
                    DebugDrawerSection {
                        EmptyView()
                    } footer: {
                        Text(note)
                    }
                }
                DebugDrawerActionRow {
                    export
                } trailing: {
                    Button("Clear", role: .destructive) {
                        selected = nil
                        onClear()
                    }
                    .debugDrawerButtonStyle(.destructive)
                    .accessibilityHint("Drops every recorded event")
                }
            }
        }

        /// A note below the list: that the filter matches nothing, or that the log is full.
        private func note(matching: Int) -> String? {
            if matching == 0 {
                "No events match “\(query.trimmingCharacters(in: .whitespacesAndNewlines))”."
            } else if events.count >= capacity {
                "The newest \(capacity.formatted()) events are kept; older ones are dropped."
            } else {
                nil
            }
        }

        /// Export All, where the system can share a file: tvOS has no share sheet, and a watch
        /// has nowhere to put a JSON file.
        @ViewBuilder private var export: some View {
            #if !os(tvOS) && !os(watchOS)
                let file = AnalyticsEventsFile(events: events, redaction: redaction)
                ShareLink(item: file, preview: SharePreview(file.fileName)) {
                    Label("Export All", systemImage: "square.and.arrow.up")
                }
                .accessibilityLabel("Export every event as a JSON file")
            #endif
        }
    }
#endif
