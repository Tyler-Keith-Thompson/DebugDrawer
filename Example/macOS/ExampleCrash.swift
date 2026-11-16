import Foundation

// The iOS example has its own copy of this file: each app is its own module, and the examples
// share no code.

/// A crash on demand, for the Crash Reports plugin to show on the next launch.
enum ExampleCrash {
    /// Launched with this argument, the app crashes as soon as it has installed Crash Reports, so
    /// the report can be checked without a hand.
    static let launchArgument = "-CrashOnLaunch"

    /// Ends the app with a Swift runtime failure, which arrives as `SIGTRAP`.
    static func crash() -> Never {
        fatalError("The example's Crash the App was used")
    }
}
