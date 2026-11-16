#if DEBUG
    /// What `NotificationsView`'s buttons do, each handed in by the caller.
    struct NotificationsActions {
        var requestAuthorization: () -> Void = {}
        var refresh: () -> Void = {}
        var send: () -> Void = {}
        var removePending: (ListedNotification.ID) -> Void = { _ in }
        var removeAllPending: () -> Void = {}
        var removeDelivered: (ListedNotification.ID) -> Void = { _ in }
        var removeAllDelivered: () -> Void = {}
    }
#endif
