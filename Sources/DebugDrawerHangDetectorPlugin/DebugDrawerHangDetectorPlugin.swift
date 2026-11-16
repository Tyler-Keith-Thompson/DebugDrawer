#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// The main thread's hangs `HangDetector.install(threshold:)` catches, newest first, each with
    /// its duration and stack, and the threshold; a badge counts the ones not yet opened.
    public struct HangDetectorPlugin: DebugDrawerPlugin {
        /// The plugin's identity in the drawer, which its badge is set under.
        static let pluginID = "HangDetectorPlugin"

        public var id: String {
            Self.pluginID
        }

        public var title = "Hangs"
        public var category = "Performance"
        public var icon = "hourglass"

        let store: HangStore

        init(store: HangStore) {
            self.store = store
        }

        public var body: some View {
            HangDetectorPluginView(store: store)
        }

        /// Clear All, found by "hang" and "main thread" too.
        public var actions: [DebugDrawerAction] {
            [
                DebugDrawerAction("Clear hangs", keywords: ["hang", "main thread", "stall"]) { [store] in
                    store.clear()
                }
            ]
        }
    }

    /// Reads the store and hands its hangs and threshold to `HangsView`, keeping which hang is open.
    struct HangDetectorPluginView: View {
        @ObservedObject var store: HangStore
        @State private var expanded: HangEvent.ID?

        var body: some View {
            HangsView(
                events: store.events,
                threshold: $store.threshold,
                expanded: $expanded,
                onOpen: { store.markSeen($0) },
                onMarkAllSeen: { store.markAllSeen() },
                onClear: { store.clear() }
            )
        }
    }
#endif
