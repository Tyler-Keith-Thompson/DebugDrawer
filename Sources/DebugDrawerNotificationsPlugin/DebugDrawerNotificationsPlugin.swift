import DebugDrawer
import SwiftUI

// The public API compiles in every configuration; the implementation under `#if DEBUG` below does
// not, so release builds get an empty view and an installer that installs nothing.

/// The APNs device token, the app's notification authorization and settings, an editor that
/// sends a pasted APNs payload as a local notification, and the pending and delivered
/// notifications, each removable.
public struct NotificationsPlugin: DebugDrawerPlugin {
    public var id: String {
        "NotificationsPlugin"
    }

    public var title = "Notifications"
    public var category = "App"
    public var icon = "bell.badge"

    #if DEBUG
        let model: NotificationsModel

        init(model: NotificationsModel) {
            self.model = model
        }
    #endif

    public var body: some View {
        #if DEBUG
            NotificationsPluginView(model: model)
        #else
            EmptyView()
        #endif
    }

    /// Refresh and the two Remove All buttons, found by "push" and "notifications" too.
    public var actions: [DebugDrawerAction] {
        #if DEBUG
            [
                DebugDrawerAction("Refresh notifications", keywords: ["notifications", "push", "pending", "delivered"]) { [model] in
                    Task { await model.refresh() }
                },
                DebugDrawerAction("Remove pending notifications", keywords: ["notifications", "push", "pending", "clear"]) { [model] in
                    model.removeAllPending()
                },
                DebugDrawerAction("Remove delivered notifications", keywords: ["notifications", "push", "delivered", "clear"]) { [model] in
                    model.removeAllDelivered()
                }
            ]
        #else
            []
        #endif
    }
}

#if DEBUG
    /// Reads the model and hands its state to `NotificationsView`; every action runs on the model.
    struct NotificationsPluginView: View {
        @ObservedObject var model: NotificationsModel
        @ObservedObject private var drawer = DebugDrawer.shared

        var body: some View {
            NotificationsView(
                registration: model.registration,
                center: model.center,
                authorizationRequest: model.authorizationRequest,
                sendState: model.sendState,
                draft: $model.draft,
                delay: $model.delay,
                redaction: drawer.redaction,
                actions: NotificationsActions(
                    requestAuthorization: { Task { await model.requestAuthorization() } },
                    refresh: { Task { await model.refresh() } },
                    send: { Task { await model.send() } },
                    removePending: { model.removePending($0) },
                    removeAllPending: { model.removeAllPending() },
                    removeDelivered: { model.removeDelivered($0) },
                    removeAllDelivered: { model.removeAllDelivered() }
                )
            )
        }
    }
#endif
