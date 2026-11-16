#if DEBUG
    import Combine
    import Foundation

    /// The log's events on the main actor, for the drawer: read again after each change the log
    /// reports, and counted as unseen until the plugin's list is on screen.
    ///
    /// Main-actor isolated, like the drawer that shows it; the log takes events from any thread.
    @MainActor
    final class AnalyticsEventsModel: ObservableObject {
        let log: AnalyticsEventLog
        /// Every event kept, the newest first.
        @Published private(set) var events: [AnalyticsEvent] = []
        /// The identity of the newest event the list has shown; later ones are unseen.
        private var seenThrough: Int
        /// Whether the plugin's list is on screen, which sees each event as it arrives.
        private var isShowing = false
        /// Called with the number of unseen events whenever it changes: the plugin's badge.
        private let onUnseenCountChange: @MainActor (Int) -> Void
        /// The number last handed to `onUnseenCountChange`.
        private var reportedUnseenCount = 0

        /// Reads `log` now and after each change it reports.
        ///
        /// - Parameters:
        ///   - log: Where the events are kept.
        ///   - onUnseenCountChange: Called with the number of unseen events whenever it changes.
        ///     Events already kept count as unseen.
        init(log: AnalyticsEventLog, onUnseenCountChange: @escaping @MainActor (Int) -> Void = { _ in }) {
            self.log = log
            self.onUnseenCountChange = onUnseenCountChange
            seenThrough = 0
            log.observe { [weak self] in
                // The change came from whichever thread recorded the event.
                Task { @MainActor in self?.reload() }
            }
            reload()
        }

        /// How many events arrived since the list was last on screen.
        var unseenCount: Int {
            events.count { $0.id > seenThrough }
        }

        /// Reads the log's events.
        func reload() {
            events = log.events
            if isShowing {
                markAllSeen()
            } else {
                reportUnseenCount()
            }
        }

        /// Records whether the list is on screen; while it is, every event is seen.
        func setShowing(_ isShowing: Bool) {
            self.isShowing = isShowing
            if isShowing {
                markAllSeen()
            }
        }

        /// Counts every event kept as seen.
        func markAllSeen() {
            seenThrough = max(seenThrough, events.first?.id ?? 0)
            reportUnseenCount()
        }

        /// Drops every event.
        func clear() {
            log.removeAll()
            reload()
        }

        private func reportUnseenCount() {
            let count = unseenCount
            guard count != reportedUnseenCount else { return }
            reportedUnseenCount = count
            onUnseenCountChange(count)
        }
    }
#endif
