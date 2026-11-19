import DebugDrawer
import SwiftUI

// The public API compiles in every configuration; the implementation under `#if DEBUG` below does
// not, so release builds get an empty view and an installer that installs nothing.

/// Clears the app's state as a fresh install leaves it: a checkbox per category with what it
/// will delete, a confirmation that lists it, and Reset, or Reset and Relaunch (Quit outside
/// macOS).
public struct AppStateResetPlugin: DebugDrawerPlugin {
    /// The plugin's identity in the drawer.
    static let pluginID = "AppStateResetPlugin"

    public var id: String {
        Self.pluginID
    }

    public var title = "Reset App State"
    public var category = "Storage"
    public var icon = "arrow.counterclockwise.circle"

    #if DEBUG
        let model: AppStateResetModel

        init(model: AppStateResetModel) {
            self.model = model
        }
    #endif

    public var body: some View {
        #if DEBUG
            AppStateResetPluginView(model: model)
        #else
            EmptyView()
        #endif
    }

    /// Counts `drawer` as one that holds the plugin; nothing is read until it is shown.
    @MainActor public func install(in drawer: DebugDrawer) {
        #if DEBUG
            model.install(in: ObjectIdentifier(drawer))
        #endif
    }

    /// Once the last drawer that held the plugin removes it, drops the plan it read (the files,
    /// keys and items each category holds). Nothing is deleted: a reset under way finishes.
    @MainActor public func uninstall(from drawer: DebugDrawer) {
        #if DEBUG
            model.uninstall(from: ObjectIdentifier(drawer))
        #endif
    }

    /// How many categories are selected ("3 selected").
    public var headerAccessory: some View {
        #if DEBUG
            AppStateResetHeaderAccessory(model: model)
        #else
            EmptyView()
        #endif
    }
}

#if DEBUG
    /// Reads the model and hands its values to `AppStateResetView`.
    struct AppStateResetPluginView: View {
        @ObservedObject var model: AppStateResetModel

        var body: some View {
            AppStateResetView(
                state: model.state,
                selection: $model.selection,
                includesDebugDrawer: Binding(
                    get: { model.includesDebugDrawer },
                    set: { includes in Task { await model.setIncludesDebugDrawer(includes) } }
                ),
                restartStyle: model.restartStyle,
                refresh: { Task { await model.refresh() } },
                reset: { restarting in Task { await model.reset(restarting: restarting) } }
            )
            .task { await model.loadIfNeeded() }
        }
    }

    /// The header's readout: reads the model.
    struct AppStateResetHeaderAccessory: View {
        @ObservedObject var model: AppStateResetModel

        var body: some View {
            AppStateResetHeaderReadout(count: model.selection.count)
        }
    }

    /// How many categories a reset would clear ("3 selected"), or "None selected".
    struct AppStateResetHeaderReadout: View {
        let count: Int

        var body: some View {
            Text(count == 0 ? "None selected" : "\(count.formatted()) selected")
        }
    }
#endif
