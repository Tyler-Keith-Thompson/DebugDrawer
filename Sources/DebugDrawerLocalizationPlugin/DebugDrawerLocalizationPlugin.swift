import DebugDrawer
import SwiftUI

// The public API compiles in every configuration; the implementation under `#if DEBUG` below does
// not, so release builds get an empty view and an installer that installs nothing.

/// Pseudo-localization and show-keys for the strings the app looks up through `Bundle`, the
/// translations a language is missing, and Apple's launch arguments for the rest. The header
/// counts the translations missing for the language the app runs in, after a pending relaunch.
public struct LocalizationPlugin: DebugDrawerPlugin {
    /// The plugin's identity in the drawer.
    nonisolated static let pluginID = "LocalizationPlugin"

    public nonisolated var id: String {
        Self.pluginID
    }

    public var title = "Localization"
    public var category = "Interface"
    public var icon = "character.bubble"

    #if DEBUG
        let model: LocalizationModel

        init(model: LocalizationModel) {
            self.model = model
        }
    #endif

    public var body: some View {
        #if DEBUG
            LocalizationPluginView(model: model)
        #else
            EmptyView()
        #endif
    }

    /// How many translations the current language is missing, so the gap shows while the
    /// plugin is closed.
    public var headerAccessory: some View {
        #if DEBUG
            LocalizationHeaderAccessory(model: model)
        #else
            EmptyView()
        #endif
    }

    /// Intercepts the app's string lookups from now on, unless another drawer already does, and
    /// reads the app's tables. Release builds intercept nothing.
    @MainActor public func install(in drawer: DebugDrawer) {
        #if DEBUG
            LocalizationInstallation.start(model, in: drawer)
        #endif
    }

    /// Stops intercepting once no drawer holds the plugin: puts `Bundle`'s lookups back (one other
    /// code replaced again since stays, and the plugin's under it calls straight through), so the
    /// app's strings show their translations again, and drops the tables read and the
    /// untranslated lookups recorded. The settings stored for the next launch stay.
    @MainActor public func uninstall(from drawer: DebugDrawer) {
        #if DEBUG
            LocalizationInstallation.stop(model, from: drawer)
        #endif
    }

    /// Each mode, found by "pseudo", "keys" and "translations" too.
    public var actions: [DebugDrawerAction] {
        #if DEBUG
            [
                DebugDrawerAction("Pseudo-localize strings", keywords: ["localization", "pseudo", "accents", "longer"]) { [model] in
                    model.mode = model.mode == .pseudoLocalized ? .standard : .pseudoLocalized
                },
                DebugDrawerAction("Show localization keys", keywords: ["localization", "keys", "strings"]) { [model] in
                    model.mode = model.mode == .showingKeys ? .standard : .showingKeys
                },
                DebugDrawerAction("Show translations", keywords: ["localization", "translations", "standard", "reset"]) { [model] in
                    model.mode = .standard
                }
            ]
        #else
            []
        #endif
    }
}

#if DEBUG
    /// Reads the model and hands its values to `LocalizationView`; it reads the tables again
    /// each time it appears, so a table the app downloaded since shows.
    struct LocalizationPluginView: View {
        @ObservedObject var model: LocalizationModel

        var body: some View {
            LocalizationView(
                mode: $model.mode,
                bundles: model.bundles,
                lookups: model.lookups,
                nextLaunch: model.nextLaunch,
                launchedWith: model.launchedWith,
                onNextLaunchChange: { model.setNextLaunch($0, isOn: $1) },
                onRefresh: { Task { await model.refresh() } }
            )
            .task { await model.refresh() }
        }
    }

    /// A pending relaunch or Foundation's pseudo-localization in effect, so an accented app
    /// says why while the plugin is closed, then the number of translations the current
    /// language is missing ("3 missing"); nothing when there's neither.
    struct LocalizationHeaderAccessory: View {
        @ObservedObject var model: LocalizationModel

        var body: some View {
            let count = model.currentMissing.count
            let parts = [
                model.isRelaunchPending ? "relaunch to apply" : model.nextLaunch.isEmpty ? nil : "whole app",
                count > 0 ? "\(count.formatted()) missing" : nil
            ].compactMap(\.self)
            if !parts.isEmpty {
                Text(parts.joined(separator: " · "))
            }
        }
    }
#endif
