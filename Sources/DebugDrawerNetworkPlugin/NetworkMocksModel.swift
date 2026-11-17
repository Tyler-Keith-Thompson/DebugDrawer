#if DEBUG
    import Foundation
    import os

    /// What went wrong reading or saving the rules, which the Mocks section shows.
    enum NetworkMocksIssue: Equatable {
        /// The saved file isn't in the format; the rules start empty.
        case unreadable
        /// The saved file is in a later format; the rules start empty.
        case unsupportedVersion(Int)
        /// A change couldn't be saved; it applies until the app quits.
        case notSaved
        /// A chosen file couldn't be read.
        case fileUnreadable

        /// The issue in a sentence, about the mocks.
        var message: String {
            message(about: "mocks")
        }

        /// The issue in a sentence, about the saved `things` ("mocks", "conditions").
        func message(about things: String) -> String {
            switch self {
            case .unreadable: "The saved \(things) couldn't be read, so none are loaded."
            case let .unsupportedVersion(version):
                "The saved \(things) are in format \(version), newer than this build reads, so none are loaded."
            case .notSaved: "The last change couldn't be saved; it lasts until the app quits."
            case .fileUnreadable: "The file couldn't be read."
            }
        }
    }

    /// The mock rules on the main actor, for the drawer: each change is saved and handed to the
    /// rules the URL protocol answers from.
    @MainActor
    final class NetworkMocksModel: ObservableObject {
        /// The model `installNetwork()` loads and the plugin shows, over the app's storage and the
        /// rules the URL protocol reads.
        static let shared = NetworkMocksModel(storage: _NetworkMockStorage(directory: _NetworkMockStorage.defaultDirectory), active: .shared)

        private static let logger = Logger(subsystem: "DebugDrawerNetworkPlugin", category: "NetworkMocksModel")

        /// Every rule, in the order they are tried.
        @Published private(set) var rules: [NetworkMockRule] = []
        /// What went wrong last, if anything.
        @Published private(set) var issue: NetworkMocksIssue?

        let storage: any NetworkMockStorage
        let active: NetworkMockRules

        /// - Parameters:
        ///   - storage: Where the rules are kept between launches.
        ///   - active: The rules requests are answered from, which each change replaces.
        init(storage: any NetworkMockStorage, active: NetworkMockRules) {
            self.storage = storage
            self.active = active
        }

        /// How many rules are enabled.
        var enabledCount: Int {
            rules.count(where: \.isEnabled)
        }

        /// Reads the saved rules and answers from them, then adds each of `rules` that isn't saved
        /// already (by id), at the end. A saved rule of the same id wins, so the drawer's edits to
        /// a rule the app adds at every launch last.
        func load(adding rules: [NetworkMockRule] = []) {
            var loaded: [NetworkMockRule] = []
            do {
                if let data = try storage.readRules() {
                    loaded = try NetworkMockRuleFile.decode(data)
                }
                issue = nil
            } catch let error as NetworkMockRuleFile.ReadError {
                Self.logger.error("Saved network mocks not loaded: \(String(describing: error), privacy: .public)")
                issue = switch error {
                case .unreadable: .unreadable
                case let .unsupportedVersion(version): .unsupportedVersion(version)
                }
            } catch {
                Self.logger.error("Saved network mocks not read: \(error.localizedDescription, privacy: .public)")
                issue = .unreadable
            }
            let added = rules.filter { rule in !loaded.contains { $0.id == rule.id } }
            self.rules = loaded + added
            if added.isEmpty {
                activate()
            } else {
                commit()
            }
        }

        /// Saves `rule`: in place of the rule with its id, or at the end.
        func save(_ rule: NetworkMockRule) {
            if let index = rules.firstIndex(where: { $0.id == rule.id }) {
                let replaced = rules[index]
                rules[index] = rule
                removeBodyFile(of: replaced)
            } else {
                rules.append(rule)
            }
            commit()
        }

        /// Turns the rule with `id` on or off.
        func setEnabled(_ isEnabled: Bool, id: NetworkMockRule.ID) {
            guard let index = rules.firstIndex(where: { $0.id == id }), rules[index].isEnabled != isEnabled else { return }
            rules[index].isEnabled = isEnabled
            commit()
        }

        /// Moves the rule with `id` `offset` places later (negative for earlier), within the list.
        func move(_ id: NetworkMockRule.ID, by offset: Int) {
            guard let index = rules.firstIndex(where: { $0.id == id }) else { return }
            let destination = min(max(index + offset, 0), rules.count - 1)
            guard destination != index else { return }
            rules.insert(rules.remove(at: index), at: destination)
            commit()
        }

        /// Deletes the rule with `id`, and its body file.
        func delete(_ id: NetworkMockRule.ID) {
            guard let index = rules.firstIndex(where: { $0.id == id }) else { return }
            let removed = rules.remove(at: index)
            removeBodyFile(of: removed)
            commit()
        }

        /// Copies the file at `url` into the storage as a body, and returns its name; `nil` when
        /// it can't be read or kept.
        func importBody(from url: URL) -> String? {
            // A file from the importer on iOS is outside the sandbox until it is accessed.
            let isAccessing = url.startAccessingSecurityScopedResource()
            defer {
                if isAccessing { url.stopAccessingSecurityScopedResource() }
            }
            do {
                let data = try Data(contentsOf: url)
                let name = try storage.addBody(data, fileExtension: url.pathExtension)
                return name
            } catch {
                Self.logger.error("Network mock body not imported: \(error.localizedDescription, privacy: .public)")
                issue = .fileUnreadable
                return nil
            }
        }

        /// A new rule that answers requests like `entry` as the server did, not yet saved. A body
        /// that isn't text is kept as a file.
        func rule(mocking entry: NetworkEntry) -> NetworkMockRule {
            var rule = NetworkMockRule(mocking: entry)
            if let data = NetworkMockRule.binaryBody(of: entry), let name = try? storage.addBody(data, fileExtension: nil) {
                rule.response.body = .file(name)
            }
            return rule
        }

        /// Saves the rules and answers from them.
        private func commit() {
            do {
                try storage.writeRules(NetworkMockRuleFile.encode(rules))
                if issue == .notSaved { issue = nil }
            } catch {
                Self.logger.error("Network mocks not saved: \(error.localizedDescription, privacy: .public)")
                issue = .notSaved
            }
            activate()
        }

        private func activate() {
            active.activate(rules, body: storage.body(named:))
        }

        /// Removes the body file `rule` named, unless a rule still names it.
        private func removeBodyFile(of rule: NetworkMockRule) {
            guard case let .file(name) = rule.response.body,
                  !rules.contains(where: { $0.response.body == .file(name) }) else { return }
            storage.removeBody(named: name)
        }
    }
#endif
