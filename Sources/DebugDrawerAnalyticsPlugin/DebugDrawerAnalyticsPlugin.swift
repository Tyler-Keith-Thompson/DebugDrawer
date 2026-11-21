import DebugDrawer
import SwiftUI

// The public API compiles in every configuration; the implementation under `#if DEBUG` below does
// not, so release builds get an empty view and an installer that installs nothing.

/// The events `AnalyticsEvents.record(_:properties:source:)` keeps, the newest first, each open
/// to its properties and JSON; a filter over names, keys and values, Export All and Clear. A
/// badge counts the events that arrived while the list was off screen.
public struct AnalyticsPlugin: DebugDrawerPlugin {
    /// The plugin's identity in the drawer, which its badge is set under.
    nonisolated static let pluginID = "AnalyticsPlugin"

    public nonisolated var id: String {
        Self.pluginID
    }

    public var title = "Analytics"
    public var category = "Logs & Network"
    public var icon = "chart.line.uptrend.xyaxis"

    #if DEBUG
        let model: AnalyticsEventsModel

        init(model: AnalyticsEventsModel) {
            self.model = model
        }
    #endif

    public var body: some View {
        #if DEBUG
            AnalyticsPluginView(model: model)
        #else
            EmptyView()
        #endif
    }

    /// How many events are kept, so the count shows while the plugin is closed.
    public var headerAccessory: some View {
        #if DEBUG
            AnalyticsHeaderAccessory(model: model)
        #else
            EmptyView()
        #endif
    }

    /// Clear, found by "events" and "tracking" too.
    public var actions: [DebugDrawerAction] {
        #if DEBUG
            [
                DebugDrawerAction("Clear analytics events", keywords: ["analytics", "events", "tracking", "clear"]) { [model] in
                    model.clear()
                }
            ]
        #else
            []
        #endif
    }

    /// Reads the log into the plugin's list after each event, again if an uninstall stopped it,
    /// and badges `drawer` with the events not yet seen. Release builds read nothing.
    @MainActor public func install(in drawer: DebugDrawer) {
        #if DEBUG
            model.install(in: drawer)
        #endif
    }

    /// Clears the plugin's badge from `drawer`. Once no drawer has the plugin, stops reading the
    /// log and drops the events the list held. The log goes on keeping the newest events
    /// `AnalyticsEvents.record` sends, as it does before install, so installing again shows them.
    @MainActor public func uninstall(from drawer: DebugDrawer) {
        #if DEBUG
            model.uninstall(from: drawer)
        #endif
    }
}

#if DEBUG
    /// Reads the model and hands its events to `AnalyticsEventsView`, keeping the filter and which
    /// event is open; while it is on screen, every event is seen.
    struct AnalyticsPluginView: View {
        @ObservedObject var model: AnalyticsEventsModel
        @ObservedObject private var drawer = DebugDrawer.shared
        @State private var query = ""
        @State private var selected: AnalyticsEvent.ID?

        var body: some View {
            AnalyticsEventsView(
                events: model.events,
                capacity: model.log.capacity,
                query: $query,
                selected: $selected,
                redaction: drawer.redaction,
                onClear: { model.clear() }
            )
            .onAppear { model.setShowing(true) }
            .onDisappear { model.setShowing(false) }
        }
    }

    /// The number of events kept ("38 events"), or nothing before the first.
    struct AnalyticsHeaderAccessory: View {
        @ObservedObject var model: AnalyticsEventsModel

        var body: some View {
            let count = model.events.count
            if count > 0 {
                Text(count == 1 ? "1 event" : "\(count.formatted()) events")
            }
        }
    }
#endif
