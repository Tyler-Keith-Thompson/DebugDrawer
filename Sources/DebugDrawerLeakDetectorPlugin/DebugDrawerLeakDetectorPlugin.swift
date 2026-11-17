import DebugDrawer
import SwiftUI

// The public API compiles in every configuration; the implementation under `#if DEBUG` below does
// not, so release builds get an empty view and an installer that installs nothing.

/// The leak suspects `LeakDetector` found, by class with a count; a badge counts the ones not
/// ignored.
public struct LeakDetectorPlugin: DebugDrawerPlugin {
    /// The plugin's identity in the drawer, which its badge is set under.
    static let pluginID = "LeakDetectorPlugin"

    public var id: String {
        Self.pluginID
    }

    public var title = "Leaks"
    public var category = "Performance"
    public var icon = "memorychip"

    #if DEBUG
        let store: LeakStore

        init(store: LeakStore) {
            self.store = store
        }
    #endif

    public var body: some View {
        #if DEBUG
            LeakDetectorPluginView(store: store)
        #else
            EmptyView()
        #endif
    }

    /// Stop Ignoring, found by "leak" and "retain cycle" too.
    public var actions: [DebugDrawerAction] {
        #if DEBUG
            [
                DebugDrawerAction("Stop ignoring leak suspects", keywords: ["leak", "retain cycle", "memory"]) { [store] in
                    store.stopIgnoring()
                }
            ]
        #else
            []
        #endif
    }
}

#if DEBUG
    /// Reads the store and hands its suspects to `LeaksView`.
    struct LeakDetectorPluginView: View {
        @ObservedObject var store: LeakStore

        var body: some View {
            LeaksView(
                suspects: store.visibleSuspects,
                ignoredCount: store.ignoredSuspectCount,
                onIgnore: { store.ignore($0) },
                onStopIgnoring: { store.stopIgnoring() }
            )
        }
    }
#endif
