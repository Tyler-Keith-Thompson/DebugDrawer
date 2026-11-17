#if DEBUG
    #if os(macOS)
        import AppKit
    #elseif os(iOS)
        import UIKit
    #endif
    import Foundation

    /// The app's own continuation path: the handler the host passed to `installDeepLink`, or,
    /// without one, the delegate method the system itself calls.
    ///
    /// A SwiftUI app's `onContinueUserActivity` has no public entry point to call, so a SwiftUI
    /// host passes a handler. Without one, an activity goes through public API alone: on iOS, a
    /// window scene delegate's `scene(_:continue:)`, then the app delegate's
    /// `application(_:continue:restorationHandler:)`; on the Mac, the app delegate's.
    struct _UserActivityDelivering: UserActivityDelivering {
        let handler: (@MainActor (NSUserActivity) -> Void)?

        func deliver(_ activity: NSUserActivity) -> UserActivityDelivery {
            if let handler {
                handler(activity)
                return .handler
            }
            #if os(iOS)
                // In a SwiftUI app the scene's delegate is SwiftUI's own, which implements
                // scene(_:continue:); on iOS 27 it passes the activity to onContinueUserActivity,
                // but nothing documents that, so a SwiftUI app is told to pass a handler instead.
                let scenes = UIApplication.shared.connectedScenes
                    .compactMap { $0 as? UIWindowScene }
                    // The scene in front first: the one a tapped link would reach.
                    .sorted { $0.activationState.frontness < $1.activationState.frontness }
                return Self.continue(
                    activity,
                    scenes: scenes.compactMap { scene in scene.delegate.map { (scene, $0) } },
                    application: .shared,
                    applicationDelegate: UIApplication.shared.delegate
                )
            #elseif os(macOS)
                return Self.continue(activity, application: .shared, applicationDelegate: NSApplication.shared.delegate)
            #else
                return .unhandled
            #endif
        }
    }

    #if os(iOS)
        extension _UserActivityDelivering {
            /// Hands `activity` to the first scene delegate that implements `scene(_:continue:)`,
            /// in the order given, or else to the app delegate's
            /// `application(_:continue:restorationHandler:)`.
            static func `continue`(
                _ activity: NSUserActivity,
                scenes: [(UIScene, any UISceneDelegate)],
                application: UIApplication,
                applicationDelegate: (any UIApplicationDelegate)?
            ) -> UserActivityDelivery {
                for (scene, delegate) in scenes where delegate.scene?(scene, continue: activity) != nil {
                    return .sceneDelegate
                }
                guard let accepted = applicationDelegate?.application?(application, continue: activity, restorationHandler: { _ in }) else {
                    return .unhandled
                }
                return accepted ? .applicationDelegate : .declined
            }
        }

        extension UIScene.ActivationState {
            /// Foreground active first, background last.
            fileprivate var frontness: Int {
                switch self {
                case .foregroundActive: 0
                case .foregroundInactive: 1
                case .background: 2
                default: 3
                }
            }
        }
    #elseif os(macOS)
        extension _UserActivityDelivering {
            /// Hands `activity` to the app delegate's `application(_:continue:restorationHandler:)`.
            static func `continue`(
                _ activity: NSUserActivity,
                application: NSApplication,
                applicationDelegate: (any NSApplicationDelegate)?
            ) -> UserActivityDelivery {
                guard let accepted = applicationDelegate?.application?(application, continue: activity, restorationHandler: { _ in }) else {
                    return .unhandled
                }
                return accepted ? .applicationDelegate : .declined
            }
        }
    #endif
#endif
