#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// The threshold, then the hangs, newest first, one of them open to its stack, then buttons
    /// that mark every hang seen and clear them all.
    struct HangsView: View {
        /// The thresholds the picker offers, besides the one in use.
        static let thresholdChoices: [Duration] = [100, 250, 500, 1000, 2000].map { .milliseconds($0) }

        let events: [HangEvent]
        @Binding var threshold: Duration
        /// The hang open to its stack, if any.
        @Binding var expanded: HangEvent.ID?
        /// The app's executable's file name, which marks the app's own frames.
        var ownImage: String?
        /// Called when a hang is opened: it is then seen.
        let onOpen: (HangEvent.ID) -> Void
        let onMarkAllSeen: () -> Void
        let onClear: () -> Void

        var body: some View {
            DebugDrawerSection {
                DebugDrawerRow("Threshold") {
                    Picker("Threshold", selection: $threshold) {
                        ForEach(choices, id: \.self) { choice in
                            Text(HangEvent.milliseconds(choice)).tag(choice)
                        }
                    }
                    .fixedSize()
                    .accessibilityHint("The shortest time the main thread must be stuck to count as a hang")
                }
                ForEach(events) { event in
                    HangRow(event: event, isExpanded: expanded == event.id, ownImage: ownImage) { toggle(event.id) }
                }
            } footer: {
                if events.isEmpty {
                    Text("No hangs. Each time the main thread is stuck for longer than the threshold, the hang appears here with its stack.")
                }
            }
            if !events.isEmpty {
                DebugDrawerActionRow {
                    Button("Mark All Seen", action: onMarkAllSeen)
                        .disabled(events.allSatisfy(\.isSeen))
                        .accessibilityHint("Clears the badge without opening each hang")
                } trailing: {
                    Button("Clear All", role: .destructive, action: onClear)
                        .debugDrawerButtonStyle(.destructive)
                        .accessibilityHint("Forgets every hang")
                }
            }
        }

        /// The fixed choices and the threshold in use, shortest first.
        private var choices: [Duration] {
            Set(Self.thresholdChoices + [threshold]).sorted()
        }

        private func toggle(_ id: HangEvent.ID) {
            if expanded == id {
                expanded = nil
            } else {
                expanded = id
                onOpen(id)
            }
        }
    }
#endif
