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
        /// The log's identity for this model's observer, while the model reads the log.
        private var observation: Int?
        /// The drawers the plugin over this model is installed in; the last to uninstall it stops
        /// the reading.
        private var installedDrawers: Set<ObjectIdentifier> = []

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
            startReading()
        }

        /// Whether the model reads the log after each change it reports.
        var isReading: Bool {
            observation != nil
        }

        /// Counts `drawer` as one the plugin is installed in, and reads the log again from now on
        /// if an uninstall stopped it.
        func install(in drawer: ObjectIdentifier) {
            installedDrawers.insert(drawer)
            startReading()
        }

        /// Uncounts `drawer`. Once no drawer has the plugin, stops reading the log and drops the
        /// events read, which clears the badge. The log keeps what `AnalyticsEvents.record` sends
        /// it, as it does before install, so installing again shows them.
        func uninstall(from drawer: ObjectIdentifier) {
            installedDrawers.remove(drawer)
            guard installedDrawers.isEmpty, let observation else { return }
            log.stopObserving(observation)
            self.observation = nil
            events = []
            reportUnseenCount()
        }

        private func startReading() {
            guard observation == nil else { return }
            observation = log.observe { [weak self] in
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
            // A change reported before an uninstall can arrive after it.
            guard isReading else { return }
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
