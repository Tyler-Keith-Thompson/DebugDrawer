#if DEBUG
    import Foundation

    /// Which instances are leak suspects, decided from lifecycle events alone: a view controller's
    /// screen dismissed, the main run loop ending a turn, an object tracked, an object deallocated.
    ///
    /// A pure value, so tests step it event by event. It knows instances by the identifier of the
    /// sentinel attached to each (`LifetimeSentinel`), never by the object, so it retains nothing.
    ///
    /// A view controller is flagged when it is still alive, and still off screen, at the end of the
    /// turn after the one its screen was dismissed in: by then the autorelease pool of the turn
    /// that dismissed it has drained, so whatever still holds it is the app's. An object tracked
    /// with a limit is flagged while more of its class are alive than the limit.
    struct LeakTracker: Equatable, Sendable {
        /// The main run loop's turns ended so far.
        private(set) var turn = 0
        private var dismissed: [UInt64: DismissedViewController] = [:]
        private var objects: [UInt64: TrackedClass] = [:]
        private var counts: [TrackedClass: Int] = [:]
        private var limits: [TrackedClass: Int] = [:]
        private var overLimitSince: [TrackedClass: Date] = [:]

        /// The dismissed view controllers the next ``endTurn(at:detached:)`` decides on: those
        /// dismissed in an earlier turn, and those already flagged, which stop being suspects once
        /// they are back on screen. In ascending order.
        var dueForCheck: [UInt64] {
            dismissed.filter { $0.value.isDue(turn: turn) }.keys.sorted()
        }

        /// Every dismissed view controller not yet forgotten: waiting for its turn, or flagged.
        var dismissedIDs: Set<UInt64> {
            Set(dismissed.keys)
        }

        /// Whether a dismissed view controller is waiting for its turn to end, so the run loop
        /// should turn again rather than sleep.
        var isWaitingForTurn: Bool {
            dismissed.values.contains(where: \.isPending)
        }

        /// Starts counting the object `id` of `type`, of which at most `maxCount` should be alive
        /// at once. An object already tracked is counted once.
        ///
        /// - Returns: The class's suspect if this object takes it over its limit, or further over.
        mutating func track(_ id: UInt64, of type: TrackedClass, maxCount: Int, at date: Date) -> [LeakSuspect] {
            guard objects[id] == nil else { return [] }
            objects[id] = type
            counts[type, default: 0] += 1
            limits[type] = maxCount
            guard counts[type, default: 0] > maxCount else { return [] }
            if overLimitSince[type] == nil {
                overLimitSince[type] = date
            }
            return suspects.filter { $0.type == type && $0.reason == .overLimit(maxCount: maxCount) }
        }

        /// Notes that the view controller `id` of `type` left the screen for good (dismissed, or
        /// removed from its parent), to be checked at the end of the next turn. One already flagged
        /// stays flagged.
        mutating func dismiss(_ id: UInt64, of type: TrackedClass) {
            if dismissed[id]?.isPending == false { return }
            dismissed[id] = DismissedViewController(type: type, state: .pending(turn: turn))
        }

        /// Forgets the instance `id`, which deallocated: a suspect no longer, and one fewer of its
        /// class alive.
        mutating func end(_ id: UInt64) {
            dismissed[id] = nil
            guard let type = objects.removeValue(forKey: id) else { return }
            let count = counts[type, default: 1] - 1
            counts[type] = count == 0 ? nil : count
            if count <= limits[type, default: 0] {
                overLimitSince[type] = nil
            }
            if count == 0 {
                limits[type] = nil
            }
        }

        /// Ends the main run loop's turn: each view controller in ``dueForCheck`` that is in
        /// `detached`, still alive and off screen, is a suspect; the others are on screen again, or
        /// gone, and are forgotten.
        ///
        /// - Parameters:
        ///   - date: When the turn ended: when a view controller flagged now was flagged.
        ///   - detached: The view controllers of ``dueForCheck`` still alive and off screen.
        /// - Returns: The suspects of each class with a view controller flagged now.
        mutating func endTurn(at date: Date, detached: Set<UInt64>) -> [LeakSuspect] {
            var flagged: Set<TrackedClass> = []
            for id in dueForCheck {
                guard let viewController = dismissed[id] else { continue }
                if !detached.contains(id) {
                    dismissed[id] = nil
                } else if viewController.isPending {
                    dismissed[id]?.state = .flagged(date)
                    flagged.insert(viewController.type)
                }
            }
            turn += 1
            return suspects.filter { $0.reason == .aliveAfterDismissal && flagged.contains($0.type) }
        }

        /// Every suspect, the most recently flagged first.
        var suspects: [LeakSuspect] {
            let dismissedSuspects = Dictionary(grouping: dismissed.values.compactMap(\.flag), by: \.type).map { type, flags in
                LeakSuspect(type: type, reason: .aliveAfterDismissal, count: flags.count, since: flags.map(\.date).min() ?? .distantPast)
            }
            let limitSuspects = overLimitSince.map { type, since in
                LeakSuspect(type: type, reason: .overLimit(maxCount: limits[type, default: 0]), count: counts[type, default: 0], since: since)
            }
            return (dismissedSuspects + limitSuspects).sorted(by: LeakSuspect.isNewer)
        }
    }

    extension LeakTracker {
        /// A view controller whose screen was dismissed, until it deallocates or is back on screen.
        fileprivate struct DismissedViewController: Equatable, Sendable {
            let type: TrackedClass
            var state: DismissalState

            var isPending: Bool {
                if case .pending = state { true } else { false }
            }

            /// Whether the end of `turn` decides on it.
            func isDue(turn current: Int) -> Bool {
                switch state {
                case let .pending(turn): turn < current
                case .flagged: true
                }
            }

            /// Its class and when it was flagged, if it was.
            var flag: DismissalFlag? {
                if case let .flagged(date) = state { DismissalFlag(type: type, date: date) } else { nil }
            }
        }
    }

    /// Where a dismissed view controller stands.
    private enum DismissalState: Equatable, Sendable {
        /// Dismissed in `turn`; checked once that turn has ended.
        case pending(turn: Int)
        /// Still alive and off screen when checked, at the date.
        case flagged(Date)
    }

    /// A flagged view controller's class and when it was flagged.
    private struct DismissalFlag {
        let type: TrackedClass
        let date: Date
    }

    extension LeakSuspect {
        /// Whether `first` sorts before `second`: the more recently flagged first, then by class and
        /// reason, so the order is the same however they arrived.
        fileprivate static func isNewer(_ first: LeakSuspect, _ second: LeakSuspect) -> Bool {
            if first.since != second.since { return first.since > second.since }
            return first.id < second.id
        }
    }
#endif
