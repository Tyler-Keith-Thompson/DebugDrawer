#if DEBUG
    import SwiftUI

    /// A plugin's section header: a button that expands or collapses the section. VoiceOver reads
    /// it as a heading named for the plugin, with whether it is expanded, pinned and badged.
    struct PluginSectionHeader: View {
        let plugin: AnyDebugDrawerPlugin
        let isExpanded: Bool
        let isPinned: Bool
        /// The plugin's badge count, if it has one.
        let badge: Int?
        /// Whether the header's context menu pins and moves it, as for a global plugin.
        let isMovable: Bool
        let toggle: () -> Void

        var body: some View {
            Button(action: toggle) {
                PluginHeaderLabel(plugin: plugin, isExpanded: isExpanded, isPinned: isPinned, badge: badge)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(plugin.title)
            .accessibilityValue(state)
            .accessibilityHint(isMovable ? "Toggles the section. Its actions pin it or move it." : "Toggles the section.")
            .accessibilityAddTraits(.isHeader)
        }

        /// The label names the plugin only, so the pin and badge the label draws are read here.
        private var state: String {
            let expansion = isExpanded ? "Expanded" : "Collapsed"
            let pin = isPinned ? ["Pinned"] : []
            let count = badge.map { ["\($0) new"] } ?? []
            return ([expansion] + pin + count).joined(separator: ", ")
        }
    }
#endif
