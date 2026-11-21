#if DEBUG
    import Combine
    import DebugDrawer
    import Foundation

    /// The hangs of this run, newest first, the newest ``limit`` kept, and the threshold the
    /// monitor uses.
    ///
    /// In memory only: a hang is about the run it happened in, and MetricKit delivers earlier
    /// runs' hangs again on its own. Main-actor isolated, like the drawer that shows and edits it.
    @MainActor
    final class HangStore: ObservableObject {
        /// How many hangs are kept; adding one more drops the oldest.
        static let limit = 50

        /// Every hang kept, newest first.
        @Published private(set) var events: [HangEvent] = []
        /// The shortest stretch that counts as a hang. Setting it tells the monitor.
        @Published var threshold: Duration {
            didSet { onThresholdChange(threshold) }
        }

        private let onThresholdChange: @MainActor (Duration) -> Void
        private let onUnseenCountChange: @MainActor (Int) -> Void
        /// The plugin's badge, counting the unseen hangs in each drawer that installed the plugin
        /// over this store.
        let badge = DebugDrawerPluginBadge(pluginID: HangDetectorPlugin.pluginID)

        /// - Parameters:
        ///   - threshold: The threshold the monitor starts with.
        ///   - onThresholdChange: Called with the new threshold when the drawer changes it.
        ///   - onUnseenCountChange: Called with the number of unseen hangs whenever the hangs
        ///     change, after ``badge`` shows it.
        init(
            threshold: Duration,
            onThresholdChange: @escaping @MainActor (Duration) -> Void = { _ in },
            onUnseenCountChange: @escaping @MainActor (Int) -> Void = { _ in }
        ) {
            self.threshold = threshold
            self.onThresholdChange = onThresholdChange
            self.onUnseenCountChange = onUnseenCountChange
        }

        /// How many hangs the developer hasn't opened.
        var unseenCount: Int {
            events.count { !$0.isSeen }
        }

        /// Keeps `event`, dropping the oldest past ``limit``.
        func add(_ event: HangEvent) {
            let sorted = (events.filter { $0.id != event.id } + [event]).sorted(by: HangEvent.isNewer)
            update(Array(sorted.prefix(Self.limit)))
        }

        /// Keeps the hangs `diagnostics` describe; ones whose JSON isn't a hang diagnostic are
        /// dropped.
        func receive(_ diagnostics: [HangDiagnostic]) {
            for diagnostic in diagnostics {
                if let event = diagnostic.event(id: UUID()) {
                    add(event)
                }
            }
        }

        /// Marks the hang with `id` as opened.
        func markSeen(_ id: HangEvent.ID) {
            update(events.map { event in
                guard event.id == id else { return event }
                var seen = event
                seen.isSeen = true
                return seen
            })
        }

        /// Marks every hang as opened.
        func markAllSeen() {
            update(events.map { event in
                var seen = event
                seen.isSeen = true
                return seen
            })
        }

        /// Forgets every hang.
        func clear() {
            update([])
        }

        private func update(_ newEvents: [HangEvent]) {
            events = newEvents
            badge.update(unseenCount)
            onUnseenCountChange(unseenCount)
        }
    }

    extension HangEvent {
        /// Whether `first` sorts before `second`: the newer first, ties by identity so the order
        /// is the same however they arrived.
        fileprivate static func isNewer(_ first: HangEvent, _ second: HangEvent) -> Bool {
            first.date == second.date ? first.id.uuidString < second.id.uuidString : first.date > second.date
        }
    }
#endif
