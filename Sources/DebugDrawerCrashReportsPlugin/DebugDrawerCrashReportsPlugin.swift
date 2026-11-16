#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// The crash reports `CrashReports.install(directory:)` keeps, newest first, each with its
    /// stack trace; a badge counts the ones not yet opened.
    public struct CrashReportsPlugin: DebugDrawerPlugin {
        /// The plugin's identity in the drawer, which its badge is set under.
        static let pluginID = "CrashReportsPlugin"

        public var id: String {
            Self.pluginID
        }

        public var title = "Crash Reports"
        public var category = "App"
        public var icon = "exclamationmark.octagon"

        let store: CrashReportStore

        init(store: CrashReportStore) {
            self.store = store
        }

        public var body: some View {
            CrashReportsPluginView(store: store)
        }

        /// Delete All, found by "crash" and "reports" too.
        public var actions: [DebugDrawerAction] {
            [
                DebugDrawerAction("Delete crash reports", keywords: ["crash", "reports", "clear"]) { [store] in
                    store.deleteAll()
                }
            ]
        }
    }

    /// Reads the store and hands its reports to `CrashReportsView`, keeping which one is open.
    struct CrashReportsPluginView: View {
        @ObservedObject var store: CrashReportStore
        @State private var expanded: CrashReport.ID?

        var body: some View {
            CrashReportsView(
                reports: store.reports,
                expanded: $expanded,
                onOpen: { store.markSeen($0) },
                onDelete: { store.delete($0) },
                onMarkAllSeen: { store.markAllSeen() },
                onDeleteAll: { store.deleteAll() }
            )
        }
    }
#endif
