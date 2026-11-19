import DebugDrawer
import Foundation
import SwiftUI

// MARK: - Plugin

// The public API compiles in every configuration; the implementation under `#if DEBUG` below does
// not, so release builds get an empty view and an installer that registers nothing.

/// Opens URLs in the app's own handler or as the system opens a tapped link, and continues
/// universal links and activities of the app's own type in the app, as the system does for a
/// tapped universal link, Handoff or a Spotlight result. Installed by
/// ``DebugDrawer/DebugDrawer/installDeepLink(presets:continueUserActivity:openURL:)``.
public struct DeepLinkPlugin: DebugDrawerPlugin {
    /// The plugin's identity in the drawer, which its saved state, HUD pin and badges are kept under.
    public nonisolated var id: String {
        "DeepLinkPlugin"
    }

    public var title = "Deep Link Tester"
    public var category = "App"
    public var icon = "link"

    #if DEBUG
        /// The model the plugin shows, or `nil` for the shared one.
        private let model: DeepLinkModel?
        /// The presets and handlers the model takes as a drawer installs the plugin.
        let configuration: DeepLinkConfiguration

        /// The plugin with no handlers: it lists ``DeepLinkPreset/bundleURLSchemes``, opens URLs
        /// through the system, and continues an activity in the app's scene or app delegate.
        @MainActor
        public init() {
            self.init(configuration: .standard)
        }

        /// - Parameters:
        ///   - model: The model to show in place of the shared one.
        ///   - configuration: The presets and handlers the model takes as a drawer installs the
        ///     plugin.
        init(model: DeepLinkModel? = nil, configuration: DeepLinkConfiguration) {
            self.model = model
            self.configuration = configuration
        }
    #else
        /// The plugin with no handlers: it lists ``DeepLinkPreset/bundleURLSchemes``, opens URLs
        /// through the system, and continues an activity in the app's scene or app delegate.
        @MainActor
        public init() {}
    #endif

    public var body: some View {
        #if DEBUG
            DeepLinkPluginView(transport: .direct(to: model ?? .shared))
        #else
            EmptyView()
        #endif
    }

    /// Counts `drawer` as one that holds the plugin, and hands the model the plugin's presets and
    /// handlers and the history kept in the drawer's defaults.
    @MainActor public func install(in drawer: DebugDrawer) {
        #if DEBUG
            let model = model ?? .shared
            model.configure(configuration, store: _DeepLinkHistoryStore(defaults: drawer.defaults))
            model.install(in: ObjectIdentifier(drawer))
        #endif
    }

    /// Once the last drawer that held the plugin removes it, forgets what came of the last URL
    /// or activity sent. The history of URLs and activities stays in the drawer's defaults.
    @MainActor public func uninstall(from drawer: DebugDrawer) {
        #if DEBUG
            (model ?? .shared).uninstall(from: ObjectIdentifier(drawer))
        #endif
    }
}

// MARK: - Convenience installer

public extension DebugDrawer {
    /// Adds the Deep Link Tester, which opens URLs and continues universal links and activities
    /// in the app.
    ///
    /// An opened URL goes to `openURL` when given, rather than to the system: the handler routes
    /// the URL as the app's own `onOpenURL` or `application(_:open:)` does and returns whether it
    /// handled it, and the plugin shows which. Without one, the system opens the URL in whichever
    /// app takes its scheme, as it does a tapped link, so a universal link opens the browser; on
    /// the Mac a scheme the app declares opens in this copy of the app. The plugin shows when the
    /// system couldn't open it, and why.
    ///
    /// A continued activity goes to `continueUserActivity` when given. A SwiftUI app passes
    /// one, since `onContinueUserActivity` has no public entry point: the handler routes the
    /// activity as the app's own continuation code does. Without one, the activity goes to the
    /// first window scene delegate that implements `scene(_:continue:)`, else to the app
    /// delegate's `application(_:continue:restorationHandler:)`; with neither, the plugin
    /// says so.
    ///
    /// The URLs opened and activities continued are kept in this drawer's defaults, so a drawer
    /// made with ``DebugDrawer/DebugDrawer/init(defaults:)`` keeps its history apart from
    /// ``DebugDrawer/DebugDrawer/shared``'s.
    ///
    /// Calling it again replaces the plugin and its handlers.
    ///
    /// - Parameters:
    ///   - presets: The URLs listed under Presets; by default one for each URL scheme the app's
    ///     Info.plist declares (``DeepLinkPreset/bundleURLSchemes``), and none when it declares
    ///     none.
    ///   - continueUserActivity: Receives each activity the plugin continues, on the main actor:
    ///     a universal link as `NSUserActivityTypeBrowsingWeb` with its `webpageURL`, or an
    ///     activity of the app's own type with its `userInfo`.
    ///   - openURL: Receives each URL the plugin opens, on the main actor, in place of the
    ///     system, and returns whether the app handled it.
    func installDeepLink(
        presets: [DeepLinkPreset] = DeepLinkPreset.bundleURLSchemes,
        continueUserActivity: (@MainActor (NSUserActivity) -> Void)? = nil,
        openURL: (@MainActor (URL) -> Bool)? = nil
    ) {
        #if DEBUG
            let plugin = DeepLinkPlugin(configuration: DeepLinkConfiguration(
                presets: presets, delivery: _UserActivityDelivering(handler: continueUserActivity), openURL: openURL
            ))
            unregisterGlobal(id: plugin.id)
            registerGlobal(plugin)
        #endif
    }

    /// Adds the Deep Link Tester with the app's own URL schemes as presets and no `openURL`.
    ///
    /// Calls resolve to ``installDeepLink(presets:continueUserActivity:openURL:)``, which takes
    /// the same arguments.
    ///
    /// - Parameter continueUserActivity: Receives each activity the plugin continues.
    @available(*, deprecated, message: "Use installDeepLink(presets:continueUserActivity:openURL:)")
    @_disfavoredOverload
    func installDeepLink(continueUserActivity: (@MainActor (NSUserActivity) -> Void)? = nil) {
        installDeepLink(presets: DeepLinkPreset.bundleURLSchemes, continueUserActivity: continueUserActivity, openURL: nil)
    }
}
