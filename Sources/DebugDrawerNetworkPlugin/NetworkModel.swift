import Combine
import DebugDrawer
import Foundation

#if DEBUG
    // The model composes the stores it already had rather than replacing them: each keeps its own
    // storage and the work it does for the URL protocol (the mock rules it answers from, the
    // conditions it applies), and their tests keep reaching them. The model is the one way in for
    // a view: it reads them into a snapshot and does what a command asks across them, including
    // what the view used to string together itself (Clear under Previous deleting the session,
    // Previous showing the newest session).

    /// The Network plugin's state and behavior, without its views: the request log, mock rules,
    /// conditioning profiles, resends and earlier sessions, read as a ``NetworkSnapshot`` and
    /// changed with a ``NetworkCommand``.
    ///
    /// The plugin's view reaches it through a `DebugDrawerPluginTransport`:
    ///
    /// ```swift
    /// let transport = DebugDrawerPluginTransport.direct(to: NetworkModel.shared)
    /// ```
    ///
    /// Capturing starts and stops with the plugin's ``NetworkPlugin/install(in:)`` and
    /// ``NetworkPlugin/uninstall(from:)``, as it does without the model. Release builds get a
    /// stand-in whose snapshot holds nothing and which ignores every command.
    @MainActor
    public final class NetworkModel: DebugDrawerPluginModel {
        /// The model over the stores `installNetwork()` fills, which the plugin shows.
        public static let shared = NetworkModel(
            store: .shared, mocks: .shared, conditions: .shared, replays: .shared, sessions: .shared
        )

        let store: NetworkStore
        let mocks: NetworkMocksModel
        let conditions: NetworkConditionsModel
        let replays: NetworkReplayModel
        let sessions: NetworkSessionsModel
        private var subscriptions: Set<AnyCancellable> = []

        /// - Parameters:
        ///   - store: The captured requests, filters, ignore list and the sources the log shows.
        ///   - mocks: The mock rules.
        ///   - conditions: The conditioning profiles.
        ///   - replays: Resends, and where each stands.
        ///   - sessions: The sessions earlier launches kept.
        init(
            store: NetworkStore,
            mocks: NetworkMocksModel,
            conditions: NetworkConditionsModel,
            replays: NetworkReplayModel,
            sessions: NetworkSessionsModel
        ) {
            self.store = store
            self.mocks = mocks
            self.conditions = conditions
            self.replays = replays
            self.sessions = sessions
            Publishers.MergeMany(
                store.objectWillChange.eraseToAnyPublisher(),
                mocks.objectWillChange.eraseToAnyPublisher(),
                conditions.objectWillChange.eraseToAnyPublisher(),
                replays.objectWillChange.eraseToAnyPublisher(),
                sessions.objectWillChange.eraseToAnyPublisher()
            )
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &subscriptions)
            // With no earlier session left, Previous has nothing to show.
            sessions.$sessions
                .sink { [weak store] kept in
                    if kept.isEmpty { store?.hidePrevious() }
                }
                .store(in: &subscriptions)
        }

        public var snapshot: NetworkSnapshot {
            NetworkSnapshot(
                log: store.logSnapshot,
                mockRules: mocks.rules,
                mocksIssue: mocks.issue,
                conditionProfiles: conditions.profiles,
                conditionsIssue: conditions.issue,
                replayStatuses: replays.statuses,
                sessions: sessions.sessions,
                unreadableSession: sessions.unreadable
            )
        }

        public func perform(_ command: NetworkCommand) {
            switch command.action {
            case let .log(change): apply(change)
            case let .sessions(change): apply(change)
            case let .mocks(change): apply(change)
            case let .conditions(change): apply(change)
            case let .replays(change): apply(change)
            }
        }

        private func apply(_ change: NetworkCommand.Log) {
            switch change {
            case let .setFilterText(text): store.filterText = text
            case let .setFilterStatus(status): store.filterStatus = status
            case let .setSource(source): show(source)
            case let .setShowsIgnored(showsIgnored): store.showsIgnored = showsIgnored
            case .clearShown: clearShown()
            case let .importArchive(url): store.importArchive(from: url)
            case let .ignore(domain): store.ignore(domain)
            case let .stopIgnoring(domain): store.stopIgnoring(domain)
            }
        }

        private func apply(_ change: NetworkCommand.Sessions) {
            switch change {
            case .reload: Task { await sessions.reload() }
            case let .show(id): Task { await showPrevious(id) }
            case let .delete(ids): Task { await deletePrevious(ids) }
            }
        }

        private func apply(_ change: NetworkCommand.Mocks) {
            switch change {
            case let .save(rule): mocks.save(rule)
            case let .setEnabled(id, isEnabled): mocks.setEnabled(isEnabled, id: id)
            case let .move(id, offset): mocks.move(id, by: offset)
            case let .delete(id): mocks.delete(id)
            case let .addBody(upload): mocks.add(upload)
            case .bodyUnreadable: mocks.noteUnreadableBody()
            }
        }

        private func apply(_ change: NetworkCommand.Conditions) {
            switch change {
            case let .save(profile): conditions.save(profile)
            case let .setEnabled(id, isEnabled): conditions.setEnabled(isEnabled, id: id)
            case let .move(id, offset): conditions.move(id, by: offset)
            case let .delete(id): conditions.delete(id)
            }
        }

        private func apply(_ change: NetworkCommand.Replays) {
            switch change {
            case let .resend(id): resend(id)
            case let .resendEdited(request, original): Task { await replays.resend(request.urlRequest, replaying: original) }
            }
        }

        /// Shows `source`; Previous shows the newest earlier session until another is picked.
        private func show(_ source: NetworkLogSource) {
            store.source = source
            if source == .previous, store.previousLog == nil, let newest = sessions.sessions.first {
                Task { await showPrevious(newest.id) }
            }
        }

        /// Clears the captured requests or the imported file, or, under Previous, deletes the
        /// session shown.
        private func clearShown() {
            if store.source == .previous, let shown = store.previousLog {
                Task { await deletePrevious([shown.summary.id]) }
            } else {
                store.clearShown()
            }
        }

        /// Reads the earlier session with `id` and shows its requests.
        private func showPrevious(_ id: NetworkSessionSummary.ID) async {
            if let log = await sessions.log(of: id) {
                store.showPrevious(log)
            }
        }

        /// Deletes the earlier sessions with `ids`, then shows the newest left, or the captured
        /// requests when none is.
        private func deletePrevious(_ ids: [NetworkSessionSummary.ID]) async {
            await sessions.delete(ids)
            if let newest = sessions.sessions.first {
                await showPrevious(newest.id)
            } else {
                store.hidePrevious()
            }
        }

        /// Sends the captured request with `id` again; nothing when the log no longer holds it.
        private func resend(_ id: NetworkEntry.ID) {
            guard let entry = store.entries.first(where: { $0.id == id }) else { return }
            Task { await replays.resend(entry) }
        }
    }
#else
    // The release stand-in: the same members, and nothing behind them.

    /// Release builds capture nothing: this stand-in's snapshot holds nothing, and it ignores every
    /// command.
    @MainActor
    public final class NetworkModel: DebugDrawerPluginModel {
        /// The stand-in model.
        public static let shared = NetworkModel()

        private init() {}

        /// Always empty.
        public var snapshot: NetworkSnapshot {
            NetworkSnapshot()
        }

        /// Does nothing.
        ///
        /// - Parameter command: Ignored.
        public func perform(_ command: NetworkCommand) {}
    }
#endif
