import DebugDrawerHangDetector
import DebugDrawerReceiver
import Foundation

/// The app's own work a sidecar's performance traces show: a deliberate freeze of the main thread,
/// which a recording lists as a hang with the stack it was stuck on, and a report load the app
/// marks as a signpost interval.
@MainActor
final class ProductionPerformance: ObservableObject {
    /// The recorder the receiver serves, made with the receiver's sessions.
    let traces: PerformanceTraces
    /// What the last Load Report took, as the screen says it.
    @Published private(set) var lastLoad = "Not loaded yet"

    init(sessions: DebugDrawerSessions) throws {
        traces = try PerformanceTraces(sessions: sessions)
    }

    /// Keeps the main thread busy for two seconds: a hang on purpose. Busy work rather than a
    /// sleep, so the stack the recording shows is this function computing, as a real hang's is.
    @inline(never)
    func freeze() {
        let end = ContinuousClock.now + .seconds(2)
        var turns = 0
        while ContinuousClock.now < end {
            turns &+= 1
        }
        lastLoad = "Froze the main thread for 2 s (\(turns) turns)"
    }

    /// Sums a few million numbers off the main thread, marked as the "Load report" interval, which a
    /// recording lists with its duration.
    func loadReport() async {
        let interval = traces.beginInterval("Load report")
        let total = await Task.detached(priority: .userInitiated) {
            (1 ... 5_000_000).reduce(0, &+)
        }.value
        traces.endInterval(interval)
        lastLoad = "Loaded report \(total % 1000)"
    }
}
