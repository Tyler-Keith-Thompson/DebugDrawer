#if DEBUG
    import Foundation
    import os

    /// The events recorded, the newest ``capacity`` kept in a ring: once full, each new event takes
    /// the oldest one's place.
    ///
    /// Events arrive from any thread or actor and `record` returns at once, so the state sits
    /// behind a lock rather than in an actor, which would make each record an asynchronous hop and
    /// could reorder events sent back to back. `OSAllocatedUnfairLock` rather than `Mutex`, which
    /// needs iOS 18; switch to `Mutex` once iOS 18 is the minimum.
    package final class AnalyticsEventLog: Sendable {
        /// The log `AnalyticsEvents.record` writes to, for the life of the app. It keeps events
        /// from the first record, before install too.
        package static let shared = AnalyticsEventLog(capacity: AnalyticsEvents.defaultCapacity)

        fileprivate struct State: Sendable {
            /// The events, in a ring: `ring[start]` is the oldest once the ring is full.
            var ring: [AnalyticsEvent] = []
            var start = 0
            var capacity: Int
            /// The identity of the next event.
            var nextID = 1
            /// Whether a change has been reported that ``events`` hasn't been read since: later
            /// changes until then report nothing, so a burst of events is one reload.
            var isChangeReported = false
            var onChange: (@Sendable () -> Void)?
            /// The identity of the observer `onChange` belongs to; the next one gets the one after.
            var observerID = 0
        }

        private let state: OSAllocatedUnfairLock<State>
        private let now: @Sendable () -> Date

        /// An empty log.
        ///
        /// - Parameters:
        ///   - capacity: How many events are kept; at least 1.
        ///   - now: The time an event is recorded at.
        package init(capacity: Int, now: @escaping @Sendable () -> Date = { Date() }) {
            // Can't fire: package API, made once in the module as `shared`, with the constant
            // AnalyticsEvents.defaultCapacity, and by tests with positive constants.
            precondition(capacity > 0, "The log keeps at least one event")
            state = OSAllocatedUnfairLock(initialState: State(capacity: capacity))
            self.now = now
        }

        /// How many events are kept at most.
        package var capacity: Int {
            state.withLock(\.capacity)
        }

        /// Keeps an event recorded now, dropping the oldest when the log is full, and reports the
        /// change unless one is already waiting to be read.
        ///
        /// - Parameter source: An empty one is none.
        /// - Complexity: O(1), amortized.
        package func record(name: String, properties: [String: AnalyticsValue], source: String?) {
            let timestamp = now()
            let onChange = state.withLock { state -> (@Sendable () -> Void)? in
                let event = AnalyticsEvent(
                    id: state.nextID, timestamp: timestamp, name: name, properties: properties,
                    source: source?.isEmpty == false ? source : nil
                )
                state.nextID += 1
                if state.ring.count < state.capacity {
                    state.ring.append(event)
                } else {
                    state.ring[state.start] = event
                    state.start = (state.start + 1) % state.capacity
                }
                return state.reportChange()
            }
            // Outside the lock: the observer may read the log.
            onChange?()
        }

        /// Every event kept, the newest first. Reading it lets the next change be reported.
        ///
        /// - Complexity: O(*n*), where *n* is the number of events kept.
        package var events: [AnalyticsEvent] {
            state.withLock { state in
                state.isChangeReported = false
                return Array((state.ring[state.start...] + state.ring[..<state.start]).reversed())
            }
        }

        /// Keeps at most `capacity` events from now on, dropping the oldest beyond it.
        ///
        /// - Parameter capacity: At least 1.
        package func resize(to capacity: Int) {
            // Can't fire: package API, called only by AnalyticsEventsInstallation, which is
            // reached from AnalyticsEvents.install(), with the positive default, and from
            // install(capacity:), which throws on a capacity below 1 first.
            precondition(capacity > 0, "The log keeps at least one event")
            let onChange = state.withLock { state -> (@Sendable () -> Void)? in
                let oldestFirst = Array(state.ring[state.start...] + state.ring[..<state.start])
                state.ring = Array(oldestFirst.suffix(capacity))
                state.start = 0
                state.capacity = capacity
                return oldestFirst.count > capacity ? state.reportChange() : nil
            }
            onChange?()
        }

        /// Drops every event.
        package func removeAll() {
            let onChange = state.withLock { state -> (@Sendable () -> Void)? in
                state.ring = []
                state.start = 0
                return state.reportChange()
            }
            onChange?()
        }

        /// Calls `onChange` after each change, from the thread that made it, until ``events`` is
        /// read; then again on the next change. Replaces the observer before it.
        ///
        /// - Returns: The observer's identity, which ``stopObserving(_:)`` takes.
        @discardableResult
        package func observe(_ onChange: @escaping @Sendable () -> Void) -> Int {
            state.withLock { state in
                state.onChange = onChange
                state.isChangeReported = false
                state.observerID += 1
                return state.observerID
            }
        }

        /// Stops calling the observer `observerID` names, unless another has replaced it since:
        /// that one keeps being called.
        ///
        /// - Parameter observerID: What ``observe(_:)`` returned.
        package func stopObserving(_ observerID: Int) {
            state.withLock { state in
                guard state.observerID == observerID else { return }
                state.onChange = nil
            }
        }

        /// Whether an observer is called on each change.
        package var isObserved: Bool {
            state.withLock { $0.onChange != nil }
        }
    }

    extension AnalyticsEventLog.State {
        /// The observer to call for a change, unless one is waiting to be read; marks it reported.
        fileprivate mutating func reportChange() -> (@Sendable () -> Void)? {
            guard !isChangeReported, let onChange else { return nil }
            isChangeReported = true
            return onChange
        }
    }
#endif
