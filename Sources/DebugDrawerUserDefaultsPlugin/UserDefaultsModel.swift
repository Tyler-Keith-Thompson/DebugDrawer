import Combine
import DebugDrawer
import Foundation

#if DEBUG
    import os

    // The suites are read and written through `UserDefaultsStorage`; the model holds values only.
    // UserDefaults answers synchronously, so every command lands before `perform` returns, in the
    // order sent, and a text field bound through a direct transport reads back what was typed. A
    // write by the app itself, seen while a view follows the changes, schedules one read on the
    // main actor.

    /// The UserDefaults plugin's state and behavior, without its views: the suites it offers, the
    /// one shown, its keys and the filters, read as a ``UserDefaultsSnapshot`` and changed with a
    /// ``UserDefaultsCommand``.
    ///
    /// The plugin's view reaches it through a `DebugDrawerPluginTransport`:
    ///
    /// ```swift
    /// let transport = DebugDrawerPluginTransport.direct(to: UserDefaultsModel.shared)
    /// ```
    ///
    /// ``UserDefaultsBrowser/install(suites:)`` names the suites it offers beside the standard
    /// defaults. Release builds get a stand-in whose snapshot holds nothing and which ignores
    /// every command.
    @MainActor
    public final class UserDefaultsModel: DebugDrawerPluginModel {
        /// The model over the app's own defaults, which the plugin shows.
        public static let shared = UserDefaultsModel(suites: [])

        @Published private var suites: [UserDefaultsSuite] = [.standard]
        @Published private var selectedSuite = UserDefaultsSuite.standard
        @Published private var entries: [DefaultsEntry] = []
        @Published private var searchText = ""
        @Published private var showOtherDomains = false

        private let storage: any UserDefaultsStorage
        private let now: () -> Date
        private var observation: AnyCancellable?
        /// How many shown views follow the changes.
        private var observers = 0
        /// The drawers the plugin is installed in; the last to remove it stops the observation.
        private var installations: Set<ObjectIdentifier> = []

        /// - Parameters:
        ///   - suites: The suite names beyond the standard defaults, such as app groups'. A
        ///     repeated name, or an empty one, is listed once or not at all.
        ///   - storage: Where the values are read and written.
        ///   - now: The time a Date key is added with.
        init(suites: [String], storage: any UserDefaultsStorage = _UserDefaultsStorage(), now: @escaping () -> Date = Date.init) {
            self.storage = storage
            self.now = now
            self.suites = Self.suites(named: suites)
        }

        public var snapshot: UserDefaultsSnapshot {
            UserDefaultsSnapshot(
                suites: suites, selectedSuite: selectedSuite, entries: entries,
                searchText: searchText, showOtherDomains: showOtherDomains
            )
        }

        public func perform(_ command: UserDefaultsCommand) {
            switch command.action {
            case let .selectSuite(suite):
                guard suites.contains(suite), suite != selectedSuite else { return }
                selectedSuite = suite
                reload()
            case let .setSearchText(text):
                searchText = text
            case let .setShowOtherDomains(shows):
                showOtherDomains = shows
            case let .set(value, key):
                storage.set(value, forKey: key, in: selectedSuite)
                reload()
            case let .add(key, type):
                storage.set(type.initialValue(now: now()), forKey: key, in: selectedSuite)
                reload()
            case let .remove(key):
                storage.removeValue(forKey: key, in: selectedSuite)
                reload()
            case .reload:
                reload()
            case .startObserving:
                startObservingChanges()
            case .stopObserving:
                stopObservingChanges()
            }
        }

        /// Offers the standard defaults and `names` from now on, showing Standard: read now if a
        /// view follows the changes, else when one next appears.
        func setSuites(_ names: [String]) {
            suites = Self.suites(named: names)
            selectedSuite = .standard
            if observers > 0 { reload() } else { entries = [] }
        }

        /// `suite`'s keys, sorted, read now: each from the first domain of persistent, argument,
        /// global and registration that holds it.
        func entries(in suite: UserDefaultsSuite) -> [DefaultsEntry] {
            var found: [String: DefaultsEntry] = [:]
            for domain in DefaultsDomain.allCases {
                for (key, value) in storage.values(in: suite, domain: domain) where found[key] == nil {
                    found[key] = DefaultsEntry(key: key, value: value, domain: domain)
                }
            }
            return found.keys.sorted().compactMap { found[$0] }
        }

        /// Counts `drawer` as one the plugin is installed in.
        func install(in drawer: ObjectIdentifier) {
            installations.insert(drawer)
        }

        /// Uncounts `drawer`; once no drawer holds the plugin, stops following the app's writes,
        /// whatever views still count as showing it, and drops the keys read. The filters and the
        /// suite shown stay.
        func uninstall(from drawer: ObjectIdentifier) {
            guard installations.remove(drawer) != nil, installations.isEmpty else { return }
            observers = 0
            observation = nil
            entries = []
        }

        /// Reads the shown suite's keys again.
        private func reload() {
            entries = entries(in: selectedSuite)
        }

        /// Reads the suite, then reads it again after each change to any suite, until each call
        /// is balanced by ``stopObservingChanges()``.
        ///
        /// A burst of writes, such as several keys set in one function, reads the suite once: a
        /// change schedules one read on the main actor, and changes before it runs schedule none.
        private func startObservingChanges() {
            observers += 1
            reload()
            guard observation == nil else { return }
            // A lock, not an actor: the flag is set on the writer's thread inside the
            // notification, which can't await.
            let isReloadScheduled = OSAllocatedUnfairLock(initialState: false)
            observation = storage.observeChanges { [weak self] in
                let schedules = isReloadScheduled.withLock { isScheduled in
                    defer { isScheduled = true }
                    return !isScheduled
                }
                guard schedules else { return }
                Task { @MainActor in
                    isReloadScheduled.withLock { $0 = false }
                    // Uninstalled meanwhile: the read is for nobody.
                    guard let self, self.observation != nil else { return }
                    self.reload()
                }
            }
        }

        /// Balances one ``startObservingChanges()``; after the last, changes are no longer read,
        /// as when the plugin is hidden.
        private func stopObservingChanges() {
            observers = max(observers - 1, 0)
            if observers == 0 { observation = nil }
        }

        /// Standard, then each non-empty name once, in order.
        private static func suites(named names: [String]) -> [UserDefaultsSuite] {
            var named: [UserDefaultsSuite] = []
            for name in names where !name.isEmpty && !named.contains(.named(name)) {
                named.append(.named(name))
            }
            return [.standard] + named
        }
    }
#else
    // The release stand-in: the same members, and nothing behind them.

    /// Release builds read no defaults: this stand-in's snapshot holds nothing, and it ignores
    /// every command.
    @MainActor
    public final class UserDefaultsModel: DebugDrawerPluginModel {
        /// The stand-in model.
        public static let shared = UserDefaultsModel()

        private init() {}

        /// Always empty.
        public var snapshot: UserDefaultsSnapshot {
            UserDefaultsSnapshot()
        }

        /// Does nothing.
        ///
        /// - Parameter command: Ignored.
        public func perform(_ command: UserDefaultsCommand) {}
    }
#endif
