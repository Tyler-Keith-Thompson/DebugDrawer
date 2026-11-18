import DebugDrawer
import SwiftUI

// The public API compiles in every configuration; the implementation under `#if DEBUG` below does
// not, so release builds get an empty view and an installer that installs nothing.

/// The app's UserDefaults: a picker of the suites, the shown suite's keys with a filter, each
/// value edited in place whatever its type, and keys added and deleted. Installed by
/// ``UserDefaultsBrowser/install(suites:)``.
public struct UserDefaultsPlugin: DebugDrawerPlugin {
    public var title = "UserDefaults"
    public var category = "Storage"
    public var icon = "cylinder.split.1x2"

    #if DEBUG
        let model: UserDefaultsModel

        init(model: UserDefaultsModel) {
            self.model = model
        }
    #endif

    public var body: some View {
        #if DEBUG
            UserDefaultsPluginView(model: model)
        #else
            EmptyView()
        #endif
    }

    /// How many keys the filters let through ("12 keys").
    public var headerAccessory: some View {
        #if DEBUG
            UserDefaultsHeaderAccessory(model: model)
        #else
            EmptyView()
        #endif
    }
}

#if DEBUG
    /// Reads the model and hands its values to `UserDefaultsBrowserView`; while shown, the list
    /// follows the app's writes.
    struct UserDefaultsPluginView: View {
        @ObservedObject var model: UserDefaultsModel
        @ObservedObject private var drawer = DebugDrawer.shared

        var body: some View {
            UserDefaultsBrowserView(
                suites: model.suites,
                selectedSuite: $model.selectedSuite,
                entries: model.filteredEntries,
                keys: model.persistentKeys,
                searchText: $model.searchText,
                showOtherDomains: $model.showOtherDomains,
                redaction: drawer.redaction,
                actions: UserDefaultsBrowserActions(
                    set: { model.set($0, forKey: $1) },
                    add: { model.add($0, type: $1) },
                    remove: { model.remove($0) },
                    reload: { model.reload() }
                )
            )
            .onAppear { model.startObservingChanges() }
            .onDisappear { model.stopObservingChanges() }
        }
    }

    /// The header's readout: reads the model, and follows the app's writes while shown, which it
    /// is while the plugin is closed too.
    struct UserDefaultsHeaderAccessory: View {
        @ObservedObject var model: UserDefaultsModel

        var body: some View {
            let count = model.filteredEntries.count
            Text(count == 1 ? "1 key" : "\(count.formatted()) keys")
                .onAppear { model.startObservingChanges() }
                .onDisappear { model.stopObservingChanges() }
        }
    }
#endif
