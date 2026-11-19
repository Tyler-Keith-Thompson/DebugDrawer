#if DEBUG
    import Foundation
    import os

    /// The WebSocket connections the interception has seen, the latest first, each with its
    /// frames, bounded in both: the earliest connection, and a connection's earliest frame, go
    /// first.
    ///
    /// The interception records from whichever queue URLSession calls it on, so the log sits
    /// behind a lock rather than in an actor: a frame is recorded before the app's completion
    /// handler runs, and a hop to an actor would leave it unrecorded when the handler looks.
    final class NetworkWebSocketRecorder: Sendable {
        /// The recorder of ``NetworkStore/shared``, which the interception writes to before any
        /// install and while the plugin `installNetwork()` registers captures.
        static let shared = NetworkWebSocketRecorder(connectionCapacity: 50, frameCapacity: 500)

        let connectionCapacity: Int
        let frameCapacity: Int
        private let log = OSAllocatedUnfairLock<[NetworkWebSocketConnection]>(initialState: [])
        private let onChange: @Sendable () -> Void
        private let delivery = OSAllocatedUnfairLock(initialState: Delivery())

        /// The store a change is shown in, and whether a read for it is scheduled.
        private struct Delivery: Sendable {
            weak var store: NetworkStore?
            var isScheduled = false
        }

        /// - Parameters:
        ///   - connectionCapacity: The most connections kept.
        ///   - frameCapacity: The most frames kept per connection.
        ///   - onChange: Called after every change, on the queue that made it.
        init(connectionCapacity: Int, frameCapacity: Int, onChange: @escaping @Sendable () -> Void = {}) {
            self.connectionCapacity = connectionCapacity
            self.frameCapacity = frameCapacity
            self.onChange = onChange
        }

        /// The connections, the latest first.
        var connections: [NetworkWebSocketConnection] {
            log.withLock { $0 }
        }

        /// Records a connection the app created.
        func open(_ connection: NetworkWebSocketConnection) {
            log.withLock { connections in
                connections.insert(connection, at: 0)
                if connections.count > max(connectionCapacity, 0) {
                    connections.removeLast(connections.count - max(connectionCapacity, 0))
                }
            }
            changed()
        }

        /// Records `frame` on the connection with the id; one no longer kept records nothing.
        func record(_ frame: NetworkWebSocketFrame, on id: NetworkWebSocketConnection.ID) {
            change(id) { $0.record(frame, capacity: frameCapacity) }
        }

        /// Marks the frame with `frameID` on the connection with `id` failed for `reason`; a frame
        /// no longer kept changes nothing.
        func fail(_ frameID: NetworkWebSocketFrame.ID, on id: NetworkWebSocketConnection.ID, _ reason: String) {
            change(id) { $0.fail(frameID, reason) }
        }

        /// Ends the connection with the id as `state` says, unless it had ended already.
        func end(_ id: NetworkWebSocketConnection.ID, _ state: NetworkWebSocketConnection.State) {
            change(id) { $0.end(state) }
        }

        /// Shows every change from now on in `store`'s connections, on the main actor.
        func showChanges(in store: NetworkStore) {
            delivery.withLock { $0.store = store }
        }

        /// Lets go of every connection; frames on one still open record nothing from then on.
        func clear() {
            log.withLock { $0.removeAll() }
            changed()
        }

        private func change(_ id: NetworkWebSocketConnection.ID, _ body: @Sendable (inout NetworkWebSocketConnection) -> Void) {
            let changed = log.withLock { connections in
                guard let index = connections.firstIndex(where: { $0.id == id }) else { return false }
                body(&connections[index])
                return true
            }
            if changed { self.changed() }
        }

        /// Tells `onChange`, and schedules a read of the latest state for the store, on the main
        /// actor, unless one is scheduled already: a busy socket then costs the store one update
        /// per turn of the main actor, not one per frame, and the store never shows an earlier
        /// state after a later one. The flag is cleared before the read, so a change after it
        /// schedules another.
        private func changed() {
            onChange()
            let schedules = delivery.withLock { delivery in
                defer { delivery.isScheduled = delivery.store != nil }
                return delivery.store != nil && !delivery.isScheduled
            }
            guard schedules else { return }
            Task { @MainActor in
                let store = delivery.withLock { delivery in
                    delivery.isScheduled = false
                    return delivery.store
                }
                store?.showWebSockets(connections)
            }
        }
    }
#endif
