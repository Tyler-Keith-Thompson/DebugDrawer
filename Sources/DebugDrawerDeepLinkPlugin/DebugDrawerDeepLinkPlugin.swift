import DebugDrawer
import Foundation
import SwiftUI

// MARK: - Plugin

// The public API compiles in every configuration; the implementation under `#if DEBUG` below does
// not, so release builds get an empty view and an installer that registers nothing.

/// Opens URLs as the system opens a tapped link, and continues universal links and activities
/// of the app's own type in the app, as the system does for a tapped universal link, Handoff
/// or a Spotlight result. Installed by ``DebugDrawer/DebugDrawer/installDeepLink(continueUserActivity:)``.
public struct DeepLinkPlugin: DebugDrawerPlugin {
    public var title = "Deep Link Tester"
    public var category = "App"
    public var icon = "link"

    #if DEBUG
        let model: DeepLinkModel

        /// The plugin with no handler: a continued activity goes to the app's scene or app delegate.
        @MainActor
        public init() {
            self.init(model: DeepLinkModel(delivery: _UserActivityDelivering(handler: nil)))
        }

        init(model: DeepLinkModel) {
            self.model = model
        }
    #else
        /// The plugin with no handler: a continued activity goes to the app's scene or app delegate.
        @MainActor
        public init() {}
    #endif

    public var body: some View {
        #if DEBUG
            DeepLinkPluginView(model: model)
        #else
            EmptyView()
        #endif
    }
}

// MARK: - Convenience installer

public extension DebugDrawer {
    /// Adds the Deep Link Tester, which opens URLs and continues universal links and activities
    /// in the app.
    ///
    /// A continued activity goes to `continueUserActivity` when given. A SwiftUI app passes
    /// one, since `onContinueUserActivity` has no public entry point: the handler routes the
    /// activity as the app's own continuation code does. Without one, the activity goes to the
    /// first window scene delegate that implements `scene(_:continue:)`, else to the app
    /// delegate's `application(_:continue:restorationHandler:)`; with neither, the plugin
    /// says so.
    ///
    /// Calling it again replaces the plugin and its handler.
    ///
    /// - Parameter continueUserActivity: Receives each activity the plugin continues, on the
    ///   main actor: a universal link as `NSUserActivityTypeBrowsingWeb` with its
    ///   `webpageURL`, or an activity of the app's own type with its `userInfo`.
    func installDeepLink(continueUserActivity: (@MainActor (NSUserActivity) -> Void)? = nil) {
        #if DEBUG
            let plugin = DeepLinkPlugin(model: DeepLinkModel(delivery: _UserActivityDelivering(handler: continueUserActivity)))
            unregisterGlobal(id: plugin.id)
            registerGlobal(plugin)
        #endif
    }
}

#if DEBUG
    // MARK: - View

    /// Reads the model and keeps the typed URL; `DeepLinkForm` draws them.
    struct DeepLinkPluginView: View {
        static let presets: [DeepLinkForm.Preset] = [
            .init(label: "HTTPS", url: "https://example.com/path"),
            .init(label: "Custom Scheme", url: "myapp://deeplink/screen"),
            .init(label: "Settings (iOS)", url: "App-prefs:root=General"),
            .init(label: "Mail", url: "mailto:test@example.com"),
            .init(label: "Tel", url: "tel:+1234567890")
        ]

        @ObservedObject var model: DeepLinkModel
        @State private var urlText = ""

        var body: some View {
            DeepLinkForm(
                urlText: $urlText,
                outcome: model.outcome,
                presets: Self.presets,
                history: model.history,
                activities: model.activities,
                onOpen: { model.open($0) },
                onContinue: { model.continue($0) },
                onClear: { model.clearHistory() }
            )
        }
    }

#endif
