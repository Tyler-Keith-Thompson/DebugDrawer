import Foundation

#if os(macOS)
    import AppKit
#elseif canImport(UIKit)
    import UIKit
#endif

/// When a stall of the app's main thread can't be seen, so isn't a hang: the notifications that
/// begin such a time and those that end it, which a `HangMonitor` follows.
///
/// A stall then is the system's work as much as the app's (deactivating its scene, taking the
/// app switcher's snapshot), and nobody is looking at the app, so Apple's own hang tracing
/// suspends there too.
package struct AppVisibility: Sendable {
    /// Where the notifications are posted.
    package let center: NotificationCenter
    /// Posted as the app goes out of sight; each pauses the monitor.
    package let hiding: [Notification.Name]
    /// Posted as the app is back in sight; each resumes it.
    package let showing: [Notification.Name]

    /// - Parameters:
    ///   - center: Where the notifications are posted.
    ///   - hiding: The notifications posted as the app goes out of sight.
    ///   - showing: The notifications posted as it is back in sight.
    package init(center: NotificationCenter, hiding: [Notification.Name], showing: [Notification.Name]) {
        self.center = center
        self.hiding = hiding
        self.showing = showing
    }

    /// The app's own lifecycle, from the system's notifications on the default center, which
    /// the system posts on the main thread, from the main thread's own work.
    ///
    /// - iOS, iPadOS, tvOS and visionOS: out of sight from resigning active until it is active
    ///   again, so the deactivation, the background, the snapshot and the return to the
    ///   foreground are none of them hangs. Entering the background and the foreground pause
    ///   too, so a monitor started while the app wasn't active (no notification says so as it
    ///   starts) stops counting at the next edge.
    /// - Mac Catalyst and macOS: out of sight only in the background (Catalyst) or hidden
    ///   (macOS). An inactive Mac app's windows are still on screen, under the pointer, so a
    ///   stall there is a spinning cursor the person sees, and is counted.
    ///
    /// It starts in sight: `UIApplication.shared` doesn't exist in every process that links this
    /// (a test runner), so its state isn't read.
    package static var system: AppVisibility {
        #if os(macOS)
            AppVisibility(
                center: .default,
                hiding: [NSApplication.willHideNotification],
                showing: [NSApplication.didUnhideNotification]
            )
        #elseif targetEnvironment(macCatalyst)
            AppVisibility(
                center: .default,
                hiding: [UIApplication.didEnterBackgroundNotification],
                showing: [UIApplication.willEnterForegroundNotification, UIApplication.didBecomeActiveNotification]
            )
        #elseif canImport(UIKit) && !os(watchOS)
            AppVisibility(
                center: .default,
                hiding: [
                    UIApplication.willResignActiveNotification,
                    UIApplication.didEnterBackgroundNotification,
                    UIApplication.willEnterForegroundNotification
                ],
                showing: [UIApplication.didBecomeActiveNotification]
            )
        #else
            AppVisibility(center: .default, hiding: [], showing: [])
        #endif
    }
}
