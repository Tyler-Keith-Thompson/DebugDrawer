#if DEBUG
    /// Where a sent activity went in the app.
    enum UserActivityDelivery: Hashable, Sendable {
        /// The handler passed to `installDeepLink(continueUserActivity:)` received it.
        case handler
        /// A window scene's delegate received it through `scene(_:continue:)`.
        case sceneDelegate
        /// The app delegate's `application(_:continue:restorationHandler:)` took it.
        case applicationDelegate
        /// The app delegate's `application(_:continue:restorationHandler:)` returned false.
        case declined
        /// Nothing in the app continues activities.
        case unhandled
    }
#endif
