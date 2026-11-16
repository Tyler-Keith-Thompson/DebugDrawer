import CoreFoundation
import Foundation

// The macOS example has its own copy of this file: each app is its own module, and the examples
// share no code.

/// A hang on demand, for the Hangs plugin to catch.
enum ExampleHang {
    /// Launched with this argument, the app blocks its main thread once it first goes idle, so
    /// the hang can be checked without a hand.
    static let launchArgument = "-HangOnLaunch"

    /// Blocks the main thread for half a second: the stall the plugin is there to catch.
    static func blockMainThread() {
        usleep(500_000)
    }

    /// Blocks the main thread as soon as its run loop first waits: the first pass is the launch,
    /// which the plugin doesn't count.
    static func blockAfterLaunch() {
        let observer = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue, false, 0) { _, _ in
            DispatchQueue.main.async { blockMainThread() }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
    }
}
