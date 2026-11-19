import DebugDrawer
import SwiftUI

// The public API compiles in every configuration; the implementation under `#if DEBUG` below does
// not, so release builds get an empty view and an installer that installs nothing.

/// The payloads `MetricKitPayloads.install(directory:)` keeps, the latest first, each open as
/// formatted JSON to copy or export; a badge counts the ones not yet opened.
public struct MetricKitPlugin: DebugDrawerPlugin {
    /// The plugin's identity in the drawer, which its badge is set under.
    nonisolated static let pluginID = "MetricKitPlugin"

    public nonisolated var id: String {
        Self.pluginID
    }

    public var title = "MetricKit"
    public var category = "Performance"
    public var icon = "chart.bar.doc.horizontal"

    #if DEBUG
        let store: MetricKitPayloadStore

        init(store: MetricKitPayloadStore) {
            self.store = store
        }
    #endif

    public var body: some View {
        #if DEBUG
            MetricKitPluginView(store: store)
        #else
            EmptyView()
        #endif
    }

    /// Keeps what MetricKit delivers from now on: subscribes to `MXMetricManager`, unless another
    /// drawer already did, and reads the payloads again if ``uninstall(from:)`` dropped them.
    /// Release builds subscribe to nothing.
    @MainActor public func install(in drawer: DebugDrawer) {
        #if DEBUG
            MetricKitPayloadsInstallation.start(store, in: drawer)
        #endif
    }

    /// Unsubscribes from `MXMetricManager` once no drawer holds the plugin, after which
    /// `MetricKitPayloads.add(json:kind:)` keeps nothing. Drops the payloads from memory; their
    /// files stay for the next install.
    @MainActor public func uninstall(from drawer: DebugDrawer) {
        #if DEBUG
            MetricKitPayloadsInstallation.stop(store, from: drawer)
        #endif
    }

    /// Delete All, found by "metrics" and "diagnostics" too.
    public var actions: [DebugDrawerAction] {
        #if DEBUG
            [
                DebugDrawerAction("Delete MetricKit payloads", keywords: ["metrickit", "metrics", "diagnostics", "payloads", "clear"]) { [store] in
                    store.deleteAll()
                }
            ]
        #else
            []
        #endif
    }
}

#if DEBUG
    /// Reads the store and hands its payloads to `MetricKitPayloadsView`, keeping which one is
    /// open.
    struct MetricKitPluginView: View {
        @ObservedObject var store: MetricKitPayloadStore
        @State private var expanded: MetricKitPayload.ID?

        var body: some View {
            MetricKitPayloadsView(
                payloads: store.payloads,
                expanded: $expanded,
                onOpen: { store.markSeen($0) },
                onDelete: { store.delete($0) },
                onMarkAllSeen: { store.markAllSeen() },
                onDeleteAll: { store.deleteAll() }
            )
        }
    }
#endif
