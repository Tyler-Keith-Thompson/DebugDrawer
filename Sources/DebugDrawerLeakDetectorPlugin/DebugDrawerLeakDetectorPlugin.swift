#if DEBUG
    import DebugDrawer
    import SwiftUI

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

        let store: LeakStore

        init(store: LeakStore) {
            self.store = store
        }

        public var body: some View {
            LeakDetectorPluginView(store: store)
        }

        /// Stop Ignoring, found by "leak" and "retain cycle" too.
        public var actions: [DebugDrawerAction] {
            [
                DebugDrawerAction("Stop ignoring leak suspects", keywords: ["leak", "retain cycle", "memory"]) { [store] in
                    store.stopIgnoring()
                }
            ]
        }
    }

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
