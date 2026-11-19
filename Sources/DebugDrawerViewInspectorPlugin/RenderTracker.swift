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
        struct Entry: Identifiable, Equatable {
            /// The name given to `.trackRenders(_:)`.
            let id: String
            /// How many body evaluations were recorded under the name.
            let count: Int
        }

        /// Every tracked name, busiest first, as of the last turn that recorded.
        @Published private(set) var entries: [Entry] = []

        /// Body evaluations by name, up to the moment; not observed.
        private(set) var counts: [String: Int] = [:]

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
            counts[name] = count
            if !isPublishPending {
                isPublishPending = true
                recorded.send()
            }
            return count
        }

        /// Forgets every count.
        func reset() {
            counts = [:]
            entries = []
        }

        /// Whether `.trackRenders(_:)` counts: from launch, and again once the View Inspector
        /// plugin is installed after an uninstall turned it off.
        var isTracking = true

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
