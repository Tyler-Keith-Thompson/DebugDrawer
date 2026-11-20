import Combine
import Foundation

#if os(macOS)
    import AppKit
#elseif canImport(UIKit)
    import UIKit
#endif

/// Whether the app is in the foreground, and when it comes there: where a reset a sidecar asked
/// for waits until it can run in front of the person.
@MainActor
package protocol AppForeground: AnyObject {
    /// Whether the app is in the foreground now.
    var isInForeground: Bool { get }
    /// Sends as the app comes to the foreground.
    var enteredForeground: AnyPublisher<Void, Never> { get }
}

/// The app's own lifecycle, from the system's notifications.
///
/// On the Mac, the foreground is being the active app: a sidecar in front of it leaves it
/// inactive, and opening it makes it active. Elsewhere it is UIKit's: from entering the
/// foreground (or becoming active, as the app launches) until entering the background. Mac
/// Catalyst takes UIKit's branch: a Catalyst app posts UIKit's notifications.
///
/// UIKit's state isn't read as it is made, since `UIApplication.shared` doesn't exist in every
/// process that links this (a test runner); it starts out of the foreground and follows the
/// notifications, the first of which a launching app posts as it becomes active, so make it as the
/// app starts. The Mac reads whether the app is active.
@MainActor
package final class _AppForeground: AppForeground {
    package private(set) var isInForeground: Bool
    private let entered = PassthroughSubject<Void, Never>()
    private var observations: [any NSObjectProtocol] = []

    package var enteredForeground: AnyPublisher<Void, Never> {
        entered.eraseToAnyPublisher()
    }

    package init() {
        #if os(macOS)
            isInForeground = NSApp?.isActive ?? false
            let entering = [NSApplication.willBecomeActiveNotification, NSApplication.didBecomeActiveNotification]
            let leaving = [NSApplication.didResignActiveNotification]
        #elseif canImport(UIKit) && !os(watchOS)
            isInForeground = false
            let entering = [UIApplication.willEnterForegroundNotification, UIApplication.didBecomeActiveNotification]
            let leaving = [UIApplication.didEnterBackgroundNotification]
        #else
            isInForeground = true
            let entering: [Notification.Name] = []
            let leaving: [Notification.Name] = []
        #endif
        // No queue, so the state changes before the post returns, as the receiver's own foreground
        // handler performs the commands waiting: whichever runs first, a reset accepted then runs.
        // The system posts these on the main thread.
        observations = entering.map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.enter()
                }
            }
        } + leaving.map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.isInForeground = false
                }
            }
        }
    }

    isolated deinit {
        for observation in observations {
            NotificationCenter.default.removeObserver(observation)
        }
    }

    private func enter() {
        isInForeground = true
        entered.send()
    }
}
