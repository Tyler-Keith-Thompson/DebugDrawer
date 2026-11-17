#if DEBUG
    import DebugDrawer

    /// What came of the last send, as the line under the field shows it.
    enum DeepLinkOutcome: Hashable {
        /// The system opened the URL.
        case opened(String)
        /// The system couldn't open the URL.
        case couldNotOpen(String)
        /// An activity went where the delivery says.
        case continued(UserActivityDelivery)

        var text: String {
            switch self {
            case let .opened(url): "Opened: \(url)"
            case .couldNotOpen: "Error: Could not open URL"
            case let .continued(delivery): delivery.text
            }
        }

        var severity: DebugDrawerIssueGlyph.Severity {
            switch self {
            case .opened, .continued(.handler), .continued(.sceneDelegate), .continued(.applicationDelegate): .ok
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
