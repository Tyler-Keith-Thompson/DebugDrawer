import Foundation

/// Crash reports in the debug drawer: what ended the app last time, shown on the next launch.
///
/// ``install(directory:)`` captures uncaught Objective-C exceptions and fatal signals (`SIGABRT`,
/// `SIGSEGV`, `SIGBUS`, `SIGILL`, `SIGFPE`, `SIGTRAP`), each handed on to the handler installed
/// before it, so a crash SDK the app also uses still sees the crash. Where MetricKit exists, the
/// crash diagnostics the system delivers are kept too.
///
/// The type exists in every build, so the install call compiles unchanged in release, where it
/// installs nothing.
public enum CrashReports {
    /// Where reports are kept unless `install(directory:)` is given another: a folder in the app's
    /// Application Support directory, named after its bundle identifier, as on macOS that
    /// directory is shared by every app that isn't sandboxed.
    public static var defaultDirectory: URL {
        URL.applicationSupportDirectory
            .appending(path: Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName, directoryHint: .isDirectory)
            .appending(path: "DebugDrawer Crash Reports", directoryHint: .isDirectory)
    }

    /// Adds the Crash Reports plugin and captures crashes from now on: in debug builds only; in
    /// release it does nothing.
    ///
    /// Call it once at startup, as early as the app can, and after any crash SDK installs its own
    /// handlers, so the plugin hands each crash on to them. It reads the report the last run
    /// left, keeps it with the others (the newest ten), raises the plugin's badge for every report
    /// not yet opened, and posts a toast for a new one. Calling it again moves where the next
    /// crash is written and installs no second handler. Removing the plugin from the drawer puts
    /// back the handlers it found.
    ///
    /// On macOS, AppKit catches an exception raised on the main thread while it handles an event,
    /// logs it and carries on, so no uncaught exception reaches the handler; set the
    /// `NSApplicationCrashOnExceptions` default to `true` to have it crash instead.
    ///
    /// - Parameter directory: Where the reports and the crash file are kept.
    @MainActor
    public static func install(directory: URL = defaultDirectory) {
        #if DEBUG
            CrashReportsInstallation.install(directory: directory)
        #endif
    }
}
