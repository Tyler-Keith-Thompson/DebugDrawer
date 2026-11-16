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
        /// Called when a hang is opened: it is then seen.
        let onOpen: (HangEvent.ID) -> Void
        let onMarkAllSeen: () -> Void
        let onClear: () -> Void
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                thresholdPicker
                if events.isEmpty {
                    Text("No hangs. Each time the main thread is stuck for longer than the threshold, the hang appears here with its stack.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(events) { event in
                        HangRow(event: event, isExpanded: expanded == event.id) { toggle(event.id) }
                        Divider()
                    }
                    buttons
                }
            }
        }

        /// The picker under a label of its own, as iOS's menu picker shows only its value: side by
        /// side, or one above the other at accessibility text sizes.
        private var thresholdPicker: some View {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
            return layout {
                // The picker carries the same label for VoiceOver.
                Text("Threshold")
                    .accessibilityHidden(true)
                Picker("Threshold", selection: $threshold) {
                    ForEach(choices, id: \.self) { choice in
                        Text(HangEvent.milliseconds(choice)).tag(choice)
                    }
                }
                .labelsHidden()
                .fixedSize()
                .accessibilityHint("The shortest time the main thread must be stuck to count as a hang")
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

        private var buttons: some View {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                : AnyLayout(HStackLayout())
            return layout {
                Button("Mark All Seen", action: onMarkAllSeen)
                    .disabled(events.allSatisfy(\.isSeen))
                    .accessibilityHint("Clears the badge without opening each hang")
                Button("Clear All", role: .destructive, action: onClear)
                    .accessibilityHint("Forgets every hang")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
#endif
