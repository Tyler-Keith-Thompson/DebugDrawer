#if DEBUG
    import Combine
    import DebugDrawer
    import Foundation

    /// The plugin's state: the URLs opened and the activities continued, each kept in the
    /// defaults, most recent first, and what came of the last send.
    @MainActor
    final class DeepLinkModel: ObservableObject {
        static let historyKey = "com.debugdrawer.deeplink.history"
        static let activitiesKey = "com.debugdrawer.deeplink.activities"
        static let maxHistory = 30

        /// URLs opened, most recent first.
        @Published private(set) var history: [String]
        /// Activities continued, most recent first, apart from the URLs opened.
        @Published private(set) var activities: [DeepLinkActivity]
        @Published private(set) var outcome: DeepLinkOutcome?

        /// The URLs listed under Presets.
        let presets: [DeepLinkPreset]

        private let delivery: any UserActivityDelivering
        private let openURL: (@MainActor (URL) -> Bool)?
        private let system: any SystemURLOpening
        private let defaults: UserDefaults

        /// - Parameters:
        ///   - presets: The URLs listed under Presets.
        ///   - delivery: Where continued activities go.
        ///   - openURL: Where opened URLs go, in place of the system, when given; it returns
        ///     whether it handled the URL.
        ///   - system: Opens URLs when there's no `openURL`.
        ///   - defaults: Where the history is kept: the drawer's own suite, apart from the app's
        ///     defaults.
        init(
            presets: [DeepLinkPreset] = [],
            delivery: any UserActivityDelivering,
            openURL: (@MainActor (URL) -> Bool)? = nil,
            system: any SystemURLOpening = _SystemURLOpening(),
            defaults: UserDefaults = .debugDrawer
        ) {
            self.presets = presets
            self.delivery = delivery
            self.openURL = openURL
            self.system = system
            self.defaults = defaults
            history = defaults.stringArray(forKey: Self.historyKey) ?? []
            // History written by another version that no longer decodes starts empty.
            activities = defaults.data(forKey: Self.activitiesKey)
                .flatMap { try? JSONDecoder().decode([DeepLinkActivity].self, from: $0) } ?? []
        }

        /// Hands `url` to the `openURL` handler, or without one opens it as the system opens a
        /// tapped link, records it, and says what came of it.
        func open(_ url: URL) async {
            let opened = url.absoluteString
            history = Self.recording(opened, in: history)
            defaults.set(history, forKey: Self.historyKey)

            if let openURL {
                outcome = openURL(url) ? .handled(opened) : .notHandled(opened)
                return
            }
            do {
                try await system.open(url)
                outcome = .opened(opened)
            } catch {
                outcome = .couldNotOpen(opened, reason: error.localizedDescription)
            }
        }

        /// Hands `activity` to the app's continuation path, and records it.
        func `continue`(_ activity: DeepLinkActivity) {
            activities = Self.recording(activity, in: activities)
            saveActivities()
            outcome = .continued(delivery.deliver(activity.makeUserActivity()))
        }

        func clearHistory() {
            history.removeAll()
            activities.removeAll()
            defaults.removeObject(forKey: Self.historyKey)
            defaults.removeObject(forKey: Self.activitiesKey)
        }

        private func saveActivities() {
            // Encoding strings, numbers and Booleans can't fail.
            guard let data = try? JSONEncoder().encode(activities) else { return }
            defaults.set(data, forKey: Self.activitiesKey)
        }

        /// `entry` at the front of `list`, any earlier copy removed, cut to `maxHistory`.
        private static func recording<Entry: Equatable>(_ entry: Entry, in list: [Entry]) -> [Entry] {
            Array(([entry] + list.filter { $0 != entry }).prefix(maxHistory))
        }
    }
#endif
