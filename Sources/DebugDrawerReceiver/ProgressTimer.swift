import Foundation

/// Calls back at a steady interval until stopped: the beat at which the continued processing
/// task reports its progress. Tests pass a fake that ticks when the test says.
@MainActor
protocol ProgressTimer: AnyObject {
    /// Calls `tick` every `interval` seconds until ``stop()``, in place of any call started before.
    func start(every interval: TimeInterval, _ tick: @escaping @MainActor () -> Void)

    /// Stops the calls; does nothing when none were started.
    func stop()
}
