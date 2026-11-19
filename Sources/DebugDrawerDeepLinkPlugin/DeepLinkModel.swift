import Combine
import DebugDrawer
import Foundation

#if DEBUG
    // The model holds values only: URLs go to the system through `SystemURLOpening` or to the
    // host's handler, activities through `UserActivityDelivering`, and the history to a
    // `DeepLinkHistoryStore`. Opening through the system answers asynchronously, so opens,
    // continues and clears each run as a task that waits for the one sent before it: an outcome
    // never lands out of order, and a clear sent after an open clears what that open recorded.
    // The typed URL changes at once, so a text field bound through a direct transport reads back
    // what was typed.

    /// The Deep Link Tester's state and behavior, without its views: the URL being typed, the
    /// presets, the URLs opened and activities continued before, and what came of the last send,
    /// read as a ``DeepLinkSnapshot`` and changed with a ``DeepLinkCommand``.
    ///
    /// The plugin's view reaches it through a `DebugDrawerPluginTransport`:
    ///
    /// ```swift
    /// let transport = DebugDrawerPluginTransport.direct(to: DeepLinkModel.shared)
    /// ```
    ///
    /// ``DebugDrawer/DebugDrawer/installDeepLink(presets:continueUserActivity:openURL:)`` gives it
    /// its presets and handlers as the drawer installs the plugin, and the history kept in that
    /// drawer's defaults. Release builds get a stand-in whose snapshot holds nothing and which
    /// ignores every command.
    @MainActor
    public final class DeepLinkModel: DebugDrawerPluginModel {
        /// The model the plugin shows, set up by the drawer that last installed it.
        public static let shared = DeepLinkModel()

        @Published private var urlText = ""
        @Published private var presets: [DeepLinkPreset]
        @Published private var history: DeepLinkHistory
        @Published private var outcome: DeepLinkOutcome?

        private var delivery: any UserActivityDelivering
        private var openURL: (@MainActor (URL) -> Bool)?
        private var store: any DeepLinkHistoryStore
        private let system: any SystemURLOpening
        /// The drawers the plugin is installed in; the last to remove it forgets the outcome.
        private var installations: Set<ObjectIdentifier> = []
        /// The last open, continue or clear started, which the next waits for.
        private var work: Task<Void, Never>?

        /// The most URLs, and the most activities, the history keeps.
        static let maxHistory = 30

        /// - Parameters:
        ///   - configuration: The presets and where opened URLs and continued activities go.
        ///   - system: Opens URLs when the configuration has no `openURL` handler.
        ///   - store: Where the history is kept.
        init(
            configuration: DeepLinkConfiguration = .standard,
            system: any SystemURLOpening = _SystemURLOpening(),
            store: any DeepLinkHistoryStore = _DeepLinkHistoryStore(defaults: .debugDrawer)
        ) {
            presets = configuration.presets
            delivery = configuration.delivery
            openURL = configuration.openURL
            self.system = system
            self.store = store
            history = store.load()
        }

        public var snapshot: DeepLinkSnapshot {
            DeepLinkSnapshot(urlText: urlText, presets: presets, history: history.urls, activities: history.activities, outcome: outcome)
        }

        public func perform(_ command: DeepLinkCommand) {
            switch command.action {
            case let .setURLText(text):
                urlText = text
            case let .open(url):
                enqueue { model in await model.open(url) }
            case let .continue(activity):
                enqueue { model in model.continue(activity) }
            case .clearHistory:
                enqueue { model in model.clearHistory() }
            }
        }

        /// Takes `configuration`'s presets and handlers, and reads the history `store` keeps,
        /// which later sends write to.
        func configure(_ configuration: DeepLinkConfiguration, store: any DeepLinkHistoryStore) {
            presets = configuration.presets
            delivery = configuration.delivery
            openURL = configuration.openURL
            self.store = store
            history = store.load()
        }

        /// Counts `drawer` as one the plugin is installed in.
        func install(in drawer: ObjectIdentifier) {
            installations.insert(drawer)
        }

        /// Uncounts `drawer`; once no drawer holds the plugin, forgets what came of the last send.
        /// The history stays, here and in the store.
        func uninstall(from drawer: ObjectIdentifier) {
            guard installations.remove(drawer) != nil, installations.isEmpty else { return }
            outcome = nil
        }

        /// Starts `body` once the work started before it is done.
        private func enqueue(_ body: @escaping @MainActor (DeepLinkModel) async -> Void) {
            work = Task { [previous = work] in
                await previous?.value
                await body(self)
            }
        }

        /// Records `url`, then hands it to the `openURL` handler, or without one opens it as the
        /// system opens a tapped link, and says what came of it.
        private func open(_ url: URL) async {
            let opened = url.absoluteString
            record { $0.urls = Self.recording(opened, in: $0.urls) }

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

        /// Records `activity`, then hands it to the app's continuation path.
        private func `continue`(_ activity: DeepLinkActivity) {
            record { $0.activities = Self.recording(activity, in: $0.activities) }
            outcome = .continued(delivery.deliver(activity.makeUserActivity()))
        }

        private func clearHistory() {
            record { $0 = DeepLinkHistory() }
        }

        /// Changes the history with `change` and keeps the result in the store.
        private func record(_ change: (inout DeepLinkHistory) -> Void) {
            change(&history)
            store.save(history)
        }

        /// `entry` at the front of `list`, any earlier copy removed, cut to `maxHistory`.
        private static func recording<Entry: Equatable>(_ entry: Entry, in list: [Entry]) -> [Entry] {
            Array(([entry] + list.filter { $0 != entry }).prefix(maxHistory))
        }
    }
#else
    // The release stand-in: the same members, and nothing behind them.

    /// Release builds open no URLs: this stand-in's snapshot holds nothing, and it ignores every
    /// command.
    @MainActor
    public final class DeepLinkModel: DebugDrawerPluginModel {
        /// The stand-in model.
        public static let shared = DeepLinkModel()

        private init() {}

        /// Always empty.
        public var snapshot: DeepLinkSnapshot {
            DeepLinkSnapshot()
        }

        /// Does nothing.
        ///
        /// - Parameter command: Ignored.
        public func perform(_ command: DeepLinkCommand) {}
    }
#endif
