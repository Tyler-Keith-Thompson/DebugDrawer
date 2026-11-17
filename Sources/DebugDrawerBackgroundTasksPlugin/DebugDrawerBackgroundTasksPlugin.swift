import DebugDrawer
import SwiftUI

// The public API compiles in every configuration; the implementation under `#if DEBUG` below does
// not, so release builds get an empty view and an installer that installs nothing.

/// The identifiers the Info.plist permits, each schedulable with its LLDB commands to copy,
/// and the pending requests, each cancellable.
public struct BackgroundTasksPlugin: DebugDrawerPlugin {
    public var id: String {
        "BackgroundTasksPlugin"
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
