#if DEBUG
    import SwiftUI

    /// A plugin's section header: a button that expands or collapses the section. VoiceOver reads
    /// it as a heading named for the plugin, with whether it is expanded, pinned, silenced and badged.
    struct PluginSectionHeader: View {
        let plugin: AnyDebugDrawerPlugin
        let isExpanded: Bool
        let isPinned: Bool
        /// The plugin's badge count, if it has one.
        let badge: Int?
        /// Whether the header's context menu pins and moves it, as for a global plugin.
        let isMovable: Bool
        /// Whether the button shows the plugin alone rather than expanding the section, as in the
        /// compact panel's list.
        var opensAlone = false
        /// Whether the plugin's badges and toasts are silenced, which the header marks with a
        /// crossed-out bell.
        var isNoticesMuted = false
        let toggle: () -> Void

        var body: some View {
            Button(action: toggle) {
                PluginHeaderLabel(plugin: plugin, isExpanded: isExpanded, isPinned: isPinned, badge: badge, isNoticesMuted: isNoticesMuted)
            }
            .debugDrawerButtonStyle(.plain)
            #if os(tvOS)
                // The focused header grows and lifts on a platter; the space keeps it off the
                // rows above and below.
                .padding(.vertical, 14)
            #endif
            .accessibilityLabel(plugin.title)
            .accessibilityValue(state)
            .accessibilityHint(hint)
            .accessibilityAddTraits(.isHeader)
        }

        /// The label names the plugin only, so the pin, silenced bell and badge the label draws are
        /// read here.
        private var state: String {
            let expansion = opensAlone ? [] : [isExpanded ? "Expanded" : "Collapsed"]
            let pin = isPinned ? ["Pinned"] : []
            let muted = isNoticesMuted ? ["Notices silenced"] : []
            let count = badge.map { ["\($0) new"] } ?? []
            return (expansion + pin + muted + count).joined(separator: ", ")
        }

        private var hint: String {
            let action = opensAlone ? "Shows the plugin." : "Toggles the section."
            return isMovable ? "\(action) Its actions pin it, move it or silence its notices." : "\(action) Its actions silence its notices."
        }
    }
#endif
