#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// More, beside the search field: Copy All, the time range, and muting or unmuting each
    /// subsystem and category the lines were logged to. Beside the field rather than in the
    /// toolbar, where the segmented picker and Delete leave it no room on one line in an iPad's
    /// drawer.
    struct ConsoleMoreMenu: View {
        @Binding var timeRange: ConsoleTimeRange
        /// The mutes, to remove from Unmute.
        let mutes: [ConsoleMute]
        /// The subsystems and categories of the lines that aren't muted, to mute.
        let muteChoices: [ConsoleMute]
        let mute: (ConsoleMute) -> Void
        let unmute: (ConsoleMute) -> Void
        /// Copies the lines the console lists.
        let copyAll: () -> Void

        var body: some View {
            Menu {
                Button("Copy All", action: copyAll)
                    .accessibilityLabel("Copy All")
                Divider()
                Picker("Time Range", selection: $timeRange) {
                    ForEach(timeRanges, id: \.self) { range in
                        Text(range.title).tag(range)
                    }
                }
                .pickerStyle(.inline)
                .accessibilityLabel("Time Range")
                muteMenus
            } label: {
                Label("More", systemImage: "ellipsis.circle")
                    .labelStyle(.iconOnly)
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .debugDrawerButtonStyle(.borderless)
            .fixedSize()
            .accessibilityLabel("More")
            .help("Copy, limit to a time range, or mute a subsystem")
        }

        @ViewBuilder private var muteMenus: some View {
            let subsystems = muteChoices.filter(\.isSubsystem)
            let categories = muteChoices.filter { !$0.isSubsystem }
            if !subsystems.isEmpty || !categories.isEmpty || !mutes.isEmpty {
                Divider()
            }
            if !subsystems.isEmpty {
                Menu("Mute Subsystem") {
                    ForEach(subsystems, id: \.self) { choice in
                        Button(choice.title) { mute(choice) }
                    }
                }
            }
            if !categories.isEmpty {
                Menu("Mute Category") {
                    ForEach(categories, id: \.self) { choice in
                        Button(choice.title) { mute(choice) }
                    }
                }
            }
            if !mutes.isEmpty {
                Menu("Unmute") {
                    ForEach(mutes, id: \.self) { muted in
                        Button(muted.title) { unmute(muted) }
                    }
                }
            }
        }

        /// The presets, and the range set from a line, while it is one.
        private var timeRanges: [ConsoleTimeRange] {
            ConsoleTimeRange.presets.contains(timeRange) ? ConsoleTimeRange.presets : ConsoleTimeRange.presets + [timeRange]
        }
    }
#endif
