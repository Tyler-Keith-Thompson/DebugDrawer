#if DEBUG
    import Combine
    import Foundation
    import os

    /// The plugin's state: the suites it offers, the one shown and its keys, read again whenever
    /// the app writes to any suite while the plugin is shown.
    @MainActor
    final class UserDefaultsModel: ObservableObject {
        /// Standard first, then each suite the host named, in its order.
        let suites: [UserDefaultsSuite]
        /// The suite whose keys show.
        @Published var selectedSuite: UserDefaultsSuite {
            didSet { if selectedSuite != oldValue { reload() } }
        }

        /// The shown suite's keys, sorted, as last read: the persistent domain's, then each key
        /// only another domain holds, from the domain whose value the suite reads.
        @Published private(set) var entries: [DefaultsEntry] = []
        @Published var searchText = ""
        /// Whether keys only the argument, global or registration domain holds show, read-only.
        @Published var showOtherDomains = false

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
            var named: [UserDefaultsSuite] = []
            for name in suites where !name.isEmpty && !named.contains(.named(name)) {
                named.append(.named(name))
            }
            self.suites = [.standard] + named
            selectedSuite = .standard
            self.storage = storage
            self.now = now
        }

        /// The entries the filters let through: unless other domains show, only the persistent
        /// domain's, and only those whose key or value contains the search text, ignoring case.
        var filteredEntries: [DefaultsEntry] {
            let shown = showOtherDomains ? entries : entries.filter { $0.domain == .persistent }
            guard !searchText.isEmpty else { return shown }
            return shown.filter { $0.matches(searchText) }
        }

        /// The keys of the shown suite's persistent domain, which a new key mustn't be.
        var persistentKeys: Set<String> {
            Set(entries.lazy.filter { $0.domain == .persistent }.map(\.key))
        }

        /// Reads the shown suite's keys again.
        func reload() {
            entries = entries(in: selectedSuite)
        }

        /// `suite`'s keys, sorted, read now: each from the first domain of persistent, argument,
        /// global and registration that holds it. A value no property list can hold, which only
        /// a registered default can be, is left out.
        func entries(in suite: UserDefaultsSuite) -> [DefaultsEntry] {
            var found: [String: DefaultsEntry] = [:]
            for domain in DefaultsDomain.allCases {
                for (key, object) in storage.values(in: suite, domain: domain) where found[key] == nil {
                    found[key] = PropertyListValue(propertyList: object).map { DefaultsEntry(key: key, value: $0, domain: domain) }
                }
            }
            return found.keys.sorted().compactMap { found[$0] }
        }

        /// Reads the suite, then reads it again after each change to any suite, until each call
        /// is balanced by ``stopObservingChanges()``: the body and the header's count each call
        /// it while shown.
        ///
        /// A burst of writes, such as several keys set in one function, reads the suite once: a
        /// change schedules one read on the main actor, and changes before it runs schedule none.
        func startObservingChanges() {
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
                    self?.reload()
                }
            }
        }

        /// Balances one ``startObservingChanges()``; after the last, changes are no longer read,
        /// as when the plugin is hidden.
        func stopObservingChanges() {
            observers = max(observers - 1, 0)
            if observers == 0 { observation = nil }
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

        /// Writes `value` for `key` in the shown suite's persistent domain.
        func set(_ value: PropertyListValue, forKey key: String) {
            storage.set(value.propertyList, forKey: key, in: selectedSuite)
            reload()
        }

        /// Adds `key` to the shown suite with a value of `type`: empty, zero, false, or for a
        /// date, now.
        func add(_ key: String, type: PropertyListType) {
            set(type.initialValue(now: now()), forKey: key)
        }

        /// Removes `key` from the shown suite's persistent domain.
        func remove(_ key: String) {
            storage.removeValue(forKey: key, in: selectedSuite)
            reload()
        }
    }

    extension DefaultsEntry {
        /// Whether the key or the value as shown contains `text`, ignoring case.
        fileprivate func matches(_ text: String) -> Bool {
            key.localizedCaseInsensitiveContains(text) || value.summary.localizedCaseInsensitiveContains(text)
        }
    }
#endif
