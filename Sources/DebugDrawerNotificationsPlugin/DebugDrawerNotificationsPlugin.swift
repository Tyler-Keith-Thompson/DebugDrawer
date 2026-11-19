import DebugDrawer
import SwiftUI

// The public API compiles in every configuration; the implementation under `#if DEBUG` below does
// not, so release builds get an empty view and an installer that installs nothing.

/// The APNs device token, the app's notification authorization and settings, an editor that
/// sends a pasted APNs payload as a local notification, and the pending and delivered
/// notifications, each removable.
public struct NotificationsPlugin: DebugDrawerPlugin {
    /// The plugin's identity in the drawer.
    static let pluginID = "NotificationsPlugin"

    public var id: String {
        Self.pluginID
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

    /// Reads the notification center again each time the app becomes active, if an uninstall
    /// stopped it. Release builds read nothing.
    @MainActor public func install(in drawer: DebugDrawer) {
        #if DEBUG
            model.install(in: ObjectIdentifier(drawer))
        #endif
    }

    /// Once no drawer has the plugin, stops observing the app becoming active and drops what was
    /// read: the settings and the pending and delivered notifications. The token the app reported
    /// stays, as do the notifications themselves.
    @MainActor public func uninstall(from drawer: DebugDrawer) {
        #if DEBUG
            model.uninstall(from: ObjectIdentifier(drawer))
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
