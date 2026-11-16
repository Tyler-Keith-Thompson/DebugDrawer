#if DEBUG
    import DebugDrawer
    import Foundation
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
        /// The app's executable's file name, which marks the app's own frames.
        let ownImage: String?

        init(store: HangStore, ownImage: String? = Bundle.main.executableURL?.lastPathComponent) {
            self.store = store
            self.ownImage = ownImage
        }

        public var body: some View {
            HangDetectorPluginView(store: store, ownImage: ownImage)
        }

        /// A warning glyph and how many hangs there are, while there are any.
        public var headerAccessory: some View {
            HangsHeaderCount(store: store)
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
        var ownImage: String?
        @State private var expanded: HangEvent.ID?

        var body: some View {
            HangsView(
                events: store.events,
                threshold: $store.threshold,
                expanded: $expanded,
                ownImage: ownImage,
                onOpen: { store.markSeen($0) },
                onMarkAllSeen: { store.markAllSeen() },
                onClear: { store.clear() }
            )
        }
    }

    /// The header's count of hangs, following the store.
    struct HangsHeaderCount: View {
        @ObservedObject var store: HangStore

        var body: some View {
            if !store.events.isEmpty {
                DebugDrawerIssueCount(.warning, count: store.events.count)
            }
        }
    }
#endif
