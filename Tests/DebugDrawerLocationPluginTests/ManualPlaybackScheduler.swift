import Combine
@testable import DebugDrawerLocationPlugin
import Foundation

/// A playback clock the test moves by hand: nothing runs until `advance(by:)`, which runs what
/// falls due in order of due time, then of scheduling, moving `now` to each one's time.
@MainActor
final class ManualPlaybackScheduler: PlaybackScheduler {
    private struct Work {
        let id: Int
        let due: Date
        let action: @MainActor () -> Void
    }

    private(set) var now: Date
    private var queue: [Work] = []
    private var nextID = 0

    /// How many actions are scheduled and not yet run or cancelled.
    var pendingCount: Int { queue.count }

    init(now: Date) {
        self.now = now
    }

    func schedule(after delay: TimeInterval, _ action: @escaping @MainActor () -> Void) -> AnyCancellable {
        let id = nextID
        nextID += 1
        queue.append(Work(id: id, due: now.addingTimeInterval(max(delay, 0)), action: action))
        return AnyCancellable { [weak self] in
            // The player cancels from the main actor, where it runs.
            MainActor.assumeIsolated { self?.queue.removeAll { $0.id == id } }
        }
    }

    func advance(by seconds: TimeInterval) {
        let end = now.addingTimeInterval(seconds)
        while let next = queue.filter({ $0.due <= end }).min(by: { ($0.due, $0.id) < ($1.due, $1.id) }) {
            queue.removeAll { $0.id == next.id }
            now = next.due
            next.action()
        }
        now = end
    }
}
