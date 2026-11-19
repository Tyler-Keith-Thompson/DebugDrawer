import DebugDrawer
import SwiftUI

// The public API compiles in every configuration; the implementation under `#if DEBUG` below does
// not, so release builds get an empty view and an installer that installs nothing.

/// The identifiers the Info.plist permits, each schedulable with its LLDB commands to copy,
/// and the pending requests, each cancellable.
public struct BackgroundTasksPlugin: DebugDrawerPlugin {
    /// The plugin's identity in the drawer.
    nonisolated static let pluginID = "BackgroundTasksPlugin"

    public nonisolated var id: String {
        Self.pluginID
    }

    public var title = "Background Tasks"
    public var category = "App"
    public var icon = "clock.arrow.circlepath"

    #if DEBUG
        let model: BackgroundTasksModel

        init(model: BackgroundTasksModel) {
            self.model = model
        }
    #endif

    public var body: some View {
        #if DEBUG
            BackgroundTasksPluginView(model: model)
        #else
            EmptyView()
        #endif
    }

    /// How many requests are pending, so the count shows while the plugin is closed.
    public var headerAccessory: some View {
        #if DEBUG
            BackgroundTasksHeaderAccessory(model: model)
        #else
            EmptyView()
        #endif
    }

    /// Refresh and Cancel All, found by "BGTaskScheduler" and "background" too.
    public var actions: [DebugDrawerAction] {
        #if DEBUG
            [
                DebugDrawerAction("Refresh background tasks", keywords: ["background", "tasks", "BGTaskScheduler", "pending"]) { [model] in
                    Task { await model.refresh() }
                },
                DebugDrawerAction("Cancel all background task requests", keywords: ["background", "tasks", "BGTaskScheduler", "clear"]) { [model] in
                    model.cancelAll()
                }
            ]
        #else
            []
        #endif
    }

    /// Reads the pending requests again each time the app becomes active, if an uninstall stopped
    /// it. Release builds read nothing.
    @MainActor public func install(in drawer: DebugDrawer) {
        #if DEBUG
            model.install(in: ObjectIdentifier(drawer))
        #endif
    }

    /// Once no drawer has the plugin, stops observing the app becoming active and drops the
    /// pending requests read; the scheduler keeps the requests themselves.
    @MainActor public func uninstall(from drawer: DebugDrawer) {
        #if DEBUG
            model.uninstall(from: ObjectIdentifier(drawer))
        #endif
    }
}

#if DEBUG
    /// Reads the model and hands its state to `BackgroundTasksView`; every action runs on the model.
    struct BackgroundTasksPluginView: View {
        @ObservedObject var model: BackgroundTasksModel

        var body: some View {
            BackgroundTasksView(
                declaration: model.declaration,
                pending: model.pending,
                schedule: model.schedule,
                actions: BackgroundTasksActions(
                    refresh: { Task { await model.refresh() } },
                    schedule: { identifier, kind in Task { await model.schedule(identifier, as: kind) } },
                    cancel: { model.cancel($0) },
                    cancelAll: { model.cancelAll() }
                )
            )
        }
    }

    /// "2 pending" while any request is; nothing otherwise.
    struct BackgroundTasksHeaderAccessory: View {
        @ObservedObject var model: BackgroundTasksModel

        var body: some View {
            if case let .loaded(requests) = model.pending, !requests.isEmpty {
                Text("\(requests.count) pending")
                    .accessibilityLabel("\(requests.count) pending \(requests.count == 1 ? "request" : "requests")")
            }
        }
    }
#endif
