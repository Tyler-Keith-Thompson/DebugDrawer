#if DEBUG
    #if os(macOS)
        import AppKit
    #elseif os(iOS)
        import UIKit
    #endif
    import Combine
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

        private let delivery: any UserActivityDelivering
        private let defaults: UserDefaults

        /// - Parameters:
        ///   - delivery: Where continued activities go.
        ///   - defaults: Where the history is kept.
        init(delivery: any UserActivityDelivering, defaults: UserDefaults = .standard) {
            self.delivery = delivery
            self.defaults = defaults
            history = defaults.stringArray(forKey: Self.historyKey) ?? []
            // History written by another version that no longer decodes starts empty.
            activities = defaults.data(forKey: Self.activitiesKey)
                .flatMap { try? JSONDecoder().decode([DeepLinkActivity].self, from: $0) } ?? []
        }

        /// Opens `url` as the system opens a tapped link, and records it.
        func open(_ url: URL) {
            let opened = url.absoluteString
            history = Self.recording(opened, in: history)
            defaults.set(history, forKey: Self.historyKey)

            #if os(macOS)
                NSWorkspace.shared.open(url)
                outcome = .opened(opened)
            #elseif os(iOS)
                UIApplication.shared.open(url) { [weak self] success in
                    Task { @MainActor in
                        self?.outcome = success ? .opened(opened) : .couldNotOpen(opened)
                    }
                }
            #endif
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
