/// Hangs in the debug drawer: each time the main thread goes longer than a threshold without
/// turning its run loop, with the stack it was stuck on.
///
/// ``install(threshold:)`` adds an observer to the main run loop and starts a watcher thread
/// that captures the main thread's stack while it is stuck. Where MetricKit exists, the hang
/// diagnostics the system delivers are kept too.
///
/// The type exists in every build, so the install call compiles unchanged in release, where it
/// starts nothing.
public enum HangDetector {
    /// The threshold unless `install(threshold:)` is given another: a quarter of a second, the
    /// shortest stall Apple counts as a hang.
    public static let defaultThreshold: Duration = .milliseconds(250)

    /// Adds the Hangs plugin and watches the main thread from now on: in debug builds only; in
    /// release it does nothing.
    ///
    /// Call it once at startup. A hang counts from the first time the main run loop waits, so
    /// the launch before it isn't one. Each hang raises the plugin's badge and posts a toast
    /// ("Main thread hung for 612 ms"). Calling it again changes the threshold and starts nothing
    /// more.
    ///
    /// - Parameter threshold: The shortest time the main thread must go without turning its run
    ///   loop to count as a hang; the drawer can change it while the app runs. Traps in debug
    ///   builds unless positive.
    @MainActor
    public static func install(threshold: Duration = defaultThreshold) {
        #if DEBUG
            HangDetectorInstallation.install(threshold: threshold)
        #endif
    }
}
