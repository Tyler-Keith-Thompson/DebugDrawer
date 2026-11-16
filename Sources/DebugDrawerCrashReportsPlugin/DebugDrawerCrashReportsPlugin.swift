#if DEBUG
    import DebugDrawer
    import Foundation
    import SwiftUI

    /// The crash reports `CrashReports.install(directory:)` keeps, newest first, each with its
    /// stack trace; a badge counts the ones not yet opened, and the header counts them all.
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
        /// The app's executable's file name, which marks the app's own frames.
        let ownImage: String?

        init(store: CrashReportStore, ownImage: String? = Bundle.main.executableURL?.lastPathComponent) {
            self.store = store
            self.ownImage = ownImage
        }

        public var body: some View {
            CrashReportsPluginView(store: store, ownImage: ownImage)
        }

        /// An error glyph and how many reports there are, while there are any.
        public var headerAccessory: some View {
            CrashReportsHeaderCount(store: store)
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
        var ownImage: String?
        @State private var expanded: CrashReport.ID?

        var body: some View {
            CrashReportsView(
                reports: store.reports,
                expanded: $expanded,
                ownImage: ownImage,
                onOpen: { store.markSeen($0) },
                onDelete: { store.delete($0) },
                onMarkAllSeen: { store.markAllSeen() },
                onDeleteAll: { store.deleteAll() }
            )
        }
    }

    /// The header's count of reports, following the store.
    struct CrashReportsHeaderCount: View {
        @ObservedObject var store: CrashReportStore

        var body: some View {
            if !store.reports.isEmpty {
                DebugDrawerIssueCount(.error, count: store.reports.count)
            }
        }
    }
#endif
