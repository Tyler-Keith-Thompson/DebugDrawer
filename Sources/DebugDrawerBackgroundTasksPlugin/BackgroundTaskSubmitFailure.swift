#if DEBUG
    /// Why `BGTaskScheduler` refused a request.
    enum BackgroundTaskSubmitFailure: Error, Hashable, Sendable {
        /// `BGTaskScheduler.Error.unavailable`.
        case unavailable
        /// `BGTaskScheduler.Error.tooManyPendingTaskRequests`.
        case tooManyPendingTaskRequests
        /// `BGTaskScheduler.Error.notPermitted`.
        case notPermitted
        /// Any other error, with the reason the system gave.
        case other(message: String)

        /// The failure a `BGTaskScheduler.Error` code stands for; a code the drawer doesn't
        /// know keeps `message`.
        ///
        /// - Parameters:
        ///   - code: The error's code in `BGTaskScheduler.errorDomain`.
        ///   - message: The error's description.
        init(schedulerErrorCode code: Int, message: String) {
            self = switch code {
            case 1: .unavailable
            case 2: .tooManyPendingTaskRequests
            case 3: .notPermitted
            default: .other(message: message)
            }
        }

        /// The failure in a word or two.
        var title: String {
            switch self {
            case .unavailable: "Unavailable"
            case .tooManyPendingTaskRequests: "Too Many Pending"
            case .notPermitted: "Not Permitted"
            case .other: "Refused"
            }
        }

        /// What the failure means and what to do about it.
        var explanation: String {
            switch self {
            case .unavailable:
                "Background tasks aren't available: the simulator doesn't run them, or Background App Refresh is off for the app. "
                    + "Try a device."
            case .tooManyPendingTaskRequests:
                "The scheduler holds one app refresh and ten processing requests at most. Cancel one, then try again."
            case .notPermitted:
                "The identifier must be in BGTaskSchedulerPermittedIdentifiers, and UIBackgroundModes must list fetch "
                    + "for app refresh or processing for processing."
            case let .other(message):
                message
            }
        }
    }
#endif
