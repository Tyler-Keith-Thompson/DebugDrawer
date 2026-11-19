import DebugDrawer
import Foundation
import SwiftUI

// The public API compiles in every configuration; the implementation under `#if DEBUG` below does
// not, so release builds get an empty view and an installer that installs nothing.

/// The main thread's hangs `HangDetector.install(threshold:)` catches, newest first, each with
/// its duration and stack, and the threshold; a badge counts the ones not yet opened.
public struct HangDetectorPlugin: DebugDrawerPlugin {
    /// The plugin's identity in the drawer, which its badge is set under.
    nonisolated static let pluginID = "HangDetectorPlugin"

    public nonisolated var id: String {
        Self.pluginID
    }

    public var title = "Hangs"
    public var category = "Performance"
    public var icon = "hourglass"

    #if DEBUG
        let store: HangStore
        /// The app's executable's file name, which marks the app's own frames.
        let ownImage: String?

        init(store: HangStore, ownImage: String? = Bundle.main.executableURL?.lastPathComponent) {
            self.store = store
            self.ownImage = ownImage
        }
    #endif

    public var body: some View {
        #if DEBUG
            HangDetectorPluginView(store: store, ownImage: ownImage)
        #else
            EmptyView()
        #endif
    }

    /// A warning glyph and how many hangs there are, while there are any.
    public var headerAccessory: some View {
        #if DEBUG
            HangsHeaderCount(store: store)
        #else
            EmptyView()
        #endif
    }

    /// Watches the main thread from now on: adds the observers to the main run loop, starts the
    /// watcher thread and subscribes to MetricKit's hang diagnostics, unless another drawer
    /// already did. Release builds start nothing.
    @MainActor public func install(in drawer: DebugDrawer) {
        #if DEBUG
            HangDetectorInstallation.start(store, in: drawer)
        #endif
    }

    /// Stops watching once no drawer holds the plugin: removes the run-loop observers, ends the
    /// watcher thread and unsubscribes from MetricKit. Forgets the hangs it caught; the threshold
    /// stays for the next install.
    @MainActor public func uninstall(from drawer: DebugDrawer) {
        #if DEBUG
            HangDetectorInstallation.stop(store, from: drawer)
        #endif
    }

    /// Clear All, found by "hang" and "main thread" too.
    public var actions: [DebugDrawerAction] {
        #if DEBUG
            [
                DebugDrawerAction("Clear hangs", keywords: ["hang", "main thread", "stall"]) { [store] in
                    store.clear()
                }
            ]
        #else
            []
        #endif
    }
}

#if DEBUG
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
