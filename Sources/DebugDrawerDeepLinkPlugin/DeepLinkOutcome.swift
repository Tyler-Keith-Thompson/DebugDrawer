#if DEBUG
    import DebugDrawer

    /// What came of the last send, as the line under the field shows it.
    enum DeepLinkOutcome: Hashable {
        /// The `openURL` handler took the URL.
        case handled(String)
        /// The `openURL` handler returned false for the URL.
        case notHandled(String)
        /// The system opened the URL.
        case opened(String)
        /// The system couldn't open the URL, for the reason given.
        case couldNotOpen(String, reason: String)
        /// An activity went where the delivery says.
        case continued(UserActivityDelivery)

        var text: String {
            switch self {
            case let .handled(url): "Handled by openURL: \(url)"
            case let .notHandled(url): "Not handled: openURL returned false for \(url)"
            case let .opened(url): "Opened by the system: \(url)"
            case let .couldNotOpen(url, reason): "Error: the system couldn't open \(url): \(reason)"
            case let .continued(delivery): delivery.text
            }
        }

        var severity: DebugDrawerIssueGlyph.Severity {
            switch self {
            case .handled, .opened, .continued(.handler), .continued(.sceneDelegate), .continued(.applicationDelegate): .ok
            case .notHandled: .warning
            case .couldNotOpen, .continued(.declined), .continued(.unhandled): .error
            }
        }
    }

    extension UserActivityDelivery {
        fileprivate var text: String {
            switch self {
            case .handler: "Continued: the continueUserActivity handler"
            case .sceneDelegate: "Continued: scene(_:continue:)"
            case .applicationDelegate: "Continued: application(_:continue:restorationHandler:)"
            case .declined: "Error: application(_:continue:restorationHandler:) returned false"
            case .unhandled: "This app has no handler: pass continueUserActivity: to installDeepLink"
            }
        }
    }
#endif
