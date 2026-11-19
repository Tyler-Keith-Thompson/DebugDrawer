#if DEBUG
    import Combine
    import Foundation

    /// How many times each view tracked with `.trackRenders(_:)` evaluated its body, by name.
    ///
    /// Bodies record into `counts`, which nothing observes: publishing from a body would invalidate
    /// every view reading the tracker in the middle of a render, and a view that both records and
    /// reads would render forever. `entries`, the published list, follows on the main queue's next
    /// turn, once per turn however many bodies recorded in it.
    @MainActor
    final class RenderTracker: ObservableObject {
        /// The tracker `.trackRenders(_:)` records into and the plugin shows.
        static let shared = RenderTracker()

        /// A tracked name and how many times its body was evaluated.
        struct Entry: Identifiable, Codable, Equatable, Sendable {
            /// The name given to `.trackRenders(_:)`.
            let id: String
            /// How many body evaluations were recorded under the name.
            let count: Int
        }

        /// Every tracked name, busiest first, as of the last turn that recorded.
        @Published private(set) var entries: [Entry] = []

        /// Body evaluations by name, up to the moment; not observed. At most ``capacity`` names.
        private(set) var counts: [String: Int] = [:]

        /// How many names ``counts`` keeps, 1,000 unless set. An app can name views from its data
        /// (`.trackRenders("Row \(id)")`), so a new name past it drops the name first counted
        /// longest ago, and memory stays bounded however many names a session meets. Setting a
        /// lower one drops the oldest names at once.
        var capacity = 1000 {
            didSet { evictPastCapacity() }
        }

        /// The names in ``counts``, in the order each was first counted.
        private var names: [String] = []

        private let recorded = PassthroughSubject<Void, Never>()
        private var isPublishPending = false
        private var publishing: AnyCancellable?

        init() {
            // The main queue's next turn: after the render pass that recorded, never during it.
            publishing = recorded
                .receive(on: DispatchQueue.main)
                .sink { [weak self] in
                    MainActor.assumeIsolated { self?.publish() }
                }
        }

        /// Counts one evaluation of the body tracked under `name`.
        ///
        /// - Parameter name: The name given to `.trackRenders(_:)`.
        /// - Returns: The count under `name`, this evaluation included.
        @discardableResult
        func record(_ name: String) -> Int {
            let count = counts[name, default: 0] + 1
            if count == 1 {
                names.append(name)
            }
            counts[name] = count
            evictPastCapacity()
            if !isPublishPending {
                isPublishPending = true
                recorded.send()
            }
            return count
        }

        /// Forgets every count.
        func reset() {
            counts = [:]
            names = []
            entries = []
        }

        /// Whether `.trackRenders(_:)` counts: from the View Inspector plugin's install to its
        /// uninstall, so an app that never installs it counts nothing and keeps no names.
        var isTracking = false

        private func evictPastCapacity() {
            // Only a name past the capacity evicts, so the array's O(n) removal stays off the path
            // that counts a name already known.
            let excess = names.count - max(capacity, 0)
            guard excess > 0 else { return }
            for name in names.prefix(excess) {
                counts[name] = nil
            }
            names.removeFirst(excess)
        }

        private func publish() {
            isPublishPending = false
            entries = Entry.busiestFirst(counts)
        }
    }

    extension RenderTracker.Entry {
        /// Counts as entries, most evaluations first, and names in order among equal counts.
        static func busiestFirst(_ counts: [String: Int]) -> [Self] {
            counts
                .map { Self(id: $0.key, count: $0.value) }
                .sorted { ($1.count, $0.id) < ($0.count, $1.id) }
        }
    }
#endif
