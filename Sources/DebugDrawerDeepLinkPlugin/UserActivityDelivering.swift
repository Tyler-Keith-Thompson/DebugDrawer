#if DEBUG
    import Foundation

    /// Hands an activity to the app's continuation path, as the system does for a tapped
    /// universal link, a Handoff or a Spotlight result.
    @MainActor
    protocol UserActivityDelivering {
        /// Delivers `activity` and says where it went.
        func deliver(_ activity: NSUserActivity) -> UserActivityDelivery
    }
#endif
