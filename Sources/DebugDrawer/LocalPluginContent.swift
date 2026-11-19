#if DEBUG
    import Observation
    import SwiftUI

    // Observable rather than a @Published value on the drawer: the drawer's list changes only when
    // what it lists by (the ID, title, icon, category, actions) does, and only the plugin's own
    // section redraws for a new body.
    /// A local plugin's latest value, which its view hands over each time the view updates.
    ///
    /// The drawer lists the plugin through ``AnyDebugDrawerPlugin/init(following:)``, whose views
    /// read the plugin from here: a new value redraws the views that show its body, HUD and header
    /// accessory, and nothing else, so a view that shows a local plugin and also observes the
    /// drawer can't loop by updating it.
    @MainActor
    @Observable
    final class LocalPluginContent {
        /// The plugin as its view last described it.
        var plugin: AnyDebugDrawerPlugin

        init(_ plugin: AnyDebugDrawerPlugin) {
            self.plugin = plugin
        }
    }

    extension AnyDebugDrawerPlugin {
        /// A plugin listed as `content`'s plugin is now, whose views and actions follow
        /// `content` as it changes.
        ///
        /// - Parameter content: The local plugin's latest value.
        @MainActor init(following content: LocalPluginContent) {
            let plugin = content.plugin
            id = plugin.id
            title = plugin.title
            icon = plugin.icon
            category = plugin.category
            typeName = plugin.typeName
            unqualifiedTypeID = plugin.unqualifiedTypeID
            actions = plugin.actions.map { action in
                DebugDrawerAction(action.title, keywords: action.keywords) {
                    content.plugin.actions.first { $0.title == action.title }?.perform()
                }
            }
            makeBody = { content.plugin.body }
            makeHUD = plugin.hasHUD ? Self.latestHUD(of: content) : nil
            makeHeaderAccessory = plugin.hasHeaderAccessory ? Self.latestHeaderAccessory(of: content) : nil
            contributeToReport = plugin.contributesToReport ? Self.latestContribution(of: content) : nil
            lifecycle = DrawerPluginLifecycle(
                install: { content.plugin.lifecycle.install($0) },
                uninstall: { content.plugin.lifecycle.uninstall($0) },
                didBecomeVisible: { content.plugin.lifecycle.didBecomeVisible($0) },
                didBecomeHidden: { content.plugin.lifecycle.didBecomeHidden($0) }
            )
        }

        private static func latestHUD(of content: LocalPluginContent) -> @MainActor () -> AnyView {
            { content.plugin.hud ?? AnyView(EmptyView()) }
        }

        private static func latestHeaderAccessory(of content: LocalPluginContent) -> @MainActor () -> AnyView {
            { content.plugin.headerAccessory ?? AnyView(EmptyView()) }
        }

        private static func latestContribution(
            of content: LocalPluginContent
        ) -> @MainActor (inout DebugDrawerReport, DebugDrawerRedaction) -> Void {
            { report, redaction in content.plugin.contribute(to: &report, redaction: redaction) }
        }

        /// Whether the drawer lists `other` as it lists this plugin: the same ID, type, title,
        /// icon, category and actions, and the same HUD, header accessory and report parts.
        func isListed(like other: AnyDebugDrawerPlugin) -> Bool {
            id == other.id && typeName == other.typeName && title == other.title && icon == other.icon
                && category == other.category && hasHUD == other.hasHUD
                && hasHeaderAccessory == other.hasHeaderAccessory && contributesToReport == other.contributesToReport
                && actions.map(\.title) == other.actions.map(\.title)
                && actions.map(\.keywords) == other.actions.map(\.keywords)
        }
    }
#endif
