import Combine
import DebugDrawer
import Foundation

#if DEBUG
    // The model composes the store and the earlier sessions rather than replacing them: the store
    // keeps the capture it runs for the process, and their tests keep reaching them. The model is
    // the one way in for a view: it reads them into a snapshot and does what a command asks across
    // them, including what the view used to string together itself (Clear under Previous deleting
    // the session, Previous showing the newest session).

    /// The Console plugin's state and behavior, without its views: the captured lines, the filter,
    /// the search, the mutes and the earlier sessions, read as a ``ConsoleSnapshot`` and changed
    /// with a ``ConsoleCommand``.
    ///
    /// The plugin's view reaches it through a `DebugDrawerPluginTransport`:
    ///
    /// ```swift
    /// let transport = DebugDrawerPluginTransport.direct(to: ConsoleModel.shared)
    /// ```
    ///
    /// Capture starts and stops with the plugin's ``ConsolePlugin/install(in:)`` and
    /// ``ConsolePlugin/uninstall(from:)``, as it does without the model. Release builds get a
    /// stand-in whose snapshot holds nothing and which ignores every command.
    @MainActor
    public final class ConsoleModel: DebugDrawerPluginModel {
        /// The model over the store `installConsole()` fills, which the plugin shows.
        public static let shared = ConsoleModel(store: .shared, sessions: .shared)

        let store: ConsoleLogStore
        let sessions: ConsoleSessionsModel
        private var subscriptions: Set<AnyCancellable> = []

        /// - Parameters:
        ///   - store: The captured lines, the filter and the sources the console shows.
        ///   - sessions: The sessions earlier launches kept.
        init(store: ConsoleLogStore, sessions: ConsoleSessionsModel) {
            self.store = store
            self.sessions = sessions
            store.objectWillChange.merge(with: sessions.objectWillChange)
                .sink { [weak self] in self?.objectWillChange.send() }
                .store(in: &subscriptions)
            // With no earlier session left, Previous has nothing to show.
            sessions.$sessions
                .sink { [weak store] kept in
                    if kept.isEmpty { store?.hidePrevious() }
                }
                .store(in: &subscriptions)
        }

        public var snapshot: ConsoleSnapshot {
            ConsoleSnapshot(log: store.logSnapshot, sessions: sessions.sessions, unreadableSession: sessions.unreadable)
        }

        public func perform(_ command: ConsoleCommand) {
            switch command.action {
            case let .filter(change): apply(change)
            case let .lines(change): apply(change)
            case let .sessions(change): apply(change)
            }
        }

        private func apply(_ change: ConsoleCommand.Filter) {
            switch change {
            case let .setSearchText(text): store.searchText = text
            case let .setSearchIsRegularExpression(isRegularExpression): store.searchIsRegularExpression = isRegularExpression
            case let .setLevel(level): store.filterLevel = level
            case let .setTimeRange(timeRange): store.timeRange = timeRange
            case let .setShowsMuted(showsMuted): store.showsMuted = showsMuted
            case let .mute(mute): store.mute(mute)
            case let .unmute(mute): store.unmute(mute)
            case .unmuteAll: store.unmuteAll()
            }
        }

        private func apply(_ change: ConsoleCommand.Lines) {
            switch change {
            case let .setSource(source): show(source)
            case .clearShown: clearShown()
            case .showEarlier: store.showEarlierPreviousLines()
            }
        }

        private func apply(_ change: ConsoleCommand.Sessions) {
            switch change {
            case .reload: Task { await sessions.reload() }
            case let .show(id): Task { await showPrevious(id) }
            case let .delete(ids): Task { await deletePrevious(ids) }
            }
        }

        /// Shows `source`; Previous shows the newest earlier session until another is picked.
        private func show(_ source: ConsoleLogSource) {
            store.source = source
            if source == .previous, store.previousLog == nil, let newest = sessions.sessions.first {
                Task { await showPrevious(newest.id) }
            }
        }

        /// Clears the captured lines, or, under Previous, deletes the session shown.
        private func clearShown() {
            if store.source == .previous, let shown = store.previousLog {
                Task { await deletePrevious([shown.summary.id]) }
            } else {
                store.clear()
            }
        }

        /// Reads the earlier session with `id` and shows its lines.
        private func showPrevious(_ id: ConsoleSessionSummary.ID) async {
            if let log = await sessions.log(of: id) {
                await store.showPrevious(log)
            }
        }

        /// Deletes the earlier sessions with `ids`, then shows the newest left, or the captured
        /// lines when none is.
        private func deletePrevious(_ ids: [ConsoleSessionSummary.ID]) async {
            await sessions.delete(ids)
            if let newest = sessions.sessions.first {
                await showPrevious(newest.id)
            } else {
                store.hidePrevious()
            }
        }
    }
#else
    // The release stand-in: the same members, and nothing behind them.

    /// Release builds capture nothing: this stand-in's snapshot holds nothing, and it ignores every
    /// command.
    @MainActor
    public final class ConsoleModel: DebugDrawerPluginModel {
        /// The stand-in model.
        public static let shared = ConsoleModel()

        private init() {}

        /// Always empty.
        public var snapshot: ConsoleSnapshot {
            ConsoleSnapshot()
        }

        /// Does nothing.
        ///
        /// - Parameter command: Ignored.
        public func perform(_ command: ConsoleCommand) {}
    }
#endif
