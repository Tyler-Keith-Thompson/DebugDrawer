#if DEBUG
    import DebugDrawer

    // The view's wording of an outcome and its glyph, kept apart from the model's value.

    extension DeepLinkOutcome {
        /// The line under the field.
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
