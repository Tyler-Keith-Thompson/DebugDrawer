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

        /// The shown suite's keys, sorted, as last read.
        @Published private(set) var entries: [DefaultsEntry] = []
        /// The keys of the shown suite's own domain, read with ``entries``.
        private var ownKeys: Set<String> = []
        @Published var searchText = ""
        @Published var showSystemKeys = false

        private let storage: any UserDefaultsStorage
        private let now: () -> Date
        private var observation: AnyCancellable?
        /// How many shown views follow the changes.
        private var observers = 0

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

        /// The entries the filters let through: unless system keys show, only the app's (in a
        /// named suite, only the suite's own, not the global domain's or registered defaults),
        /// and only those whose key or value contains the search text, ignoring case.
        var filteredEntries: [DefaultsEntry] {
            let shown = showSystemKeys ? entries : entries.filter { !isSystemKeyOfShownSuite($0.key) }
            guard !searchText.isEmpty else { return shown }
            return shown.filter { $0.matches(searchText) }
        }

        private static let systemPrefixes = [
            "NS", "Apple", "AK", "com.apple.", "WebKit",
            "Country", "AddressBook", "PKLog", "INNext",
            "METAL_", "MTL", "CTDirtyCount"
        ]

        /// Whether the system or a framework, not the app, wrote the key, judged by its prefix.
        static func isSystemKey(_ key: String) -> Bool {
            systemPrefixes.contains { key.hasPrefix($0) }
        }

        /// Whether the key is the system's: in the standard defaults, by its prefix; in a named
        /// suite, any key outside the suite's own domain.
        private func isSystemKeyOfShownSuite(_ key: String) -> Bool {
            switch selectedSuite {
            case .standard: Self.isSystemKey(key)
            case .named: !ownKeys.contains(key)
            }
        }

        /// Reads the shown suite's keys again.
        func reload() {
            ownKeys = storage.ownKeys(in: selectedSuite)
            entries = entries(in: selectedSuite)
        }

        /// `suite`'s keys, sorted, read now; a value no property list holds, which only a
        /// registered default can be, is left out.
        func entries(in suite: UserDefaultsSuite) -> [DefaultsEntry] {
            let values = storage.values(in: suite)
            return values.keys.sorted().compactMap { key in
                values[key].flatMap(PropertyListValue.init(propertyList:)).map { DefaultsEntry(key: key, value: $0) }
            }
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

        /// Writes `value` for `key` in the shown suite.
        func set(_ value: PropertyListValue, forKey key: String) {
            storage.set(value.propertyList, forKey: key, in: selectedSuite)
            reload()
        }

        /// Adds `key` to the shown suite with a value of `type`: empty, zero, false, or for a
        /// date, now.
        func add(_ key: String, type: PropertyListType) {
            set(type.initialValue(now: now()), forKey: key)
        }

        /// Removes `key` from the shown suite.
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
