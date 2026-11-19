import Combine
import DebugDrawer
import Foundation

#if DEBUG
    // The stores are read and deleted from through `CookieJar`; the model holds values only. The
    // stores answer asynchronously, so a command that reads or deletes starts work that lands in a
    // later snapshot, and each waits for the one before it: a delete sent after a refresh is never
    // undone by the refresh's older list. The filter changes at once, so a text field bound
    // through a direct transport reads back what was typed.

    /// The HTTP Cookies plugin's state and behavior, without its views: every store's cookies and
    /// the filter, read as a ``CookiesSnapshot`` and changed with a ``CookiesCommand``.
    ///
    /// The plugin's view reaches it through a `DebugDrawerPluginTransport`:
    ///
    /// ```swift
    /// let transport = DebugDrawerPluginTransport.direct(to: CookiesModel.shared)
    /// ```
    ///
    /// Release builds get a stand-in whose snapshot holds nothing and which ignores every command.
    @MainActor
    public final class CookiesModel: DebugDrawerPluginModel {
        /// The model over the app's own cookie stores, which the plugin shows.
        public static let shared = CookiesModel()

        @Published private var contents = CookiesContents.unread
        @Published private var filter = ""

        private nonisolated let jar: any CookieJar
        /// The drawers the plugin is installed in; the last to remove it drops the cookies read.
        private var installations: Set<ObjectIdentifier> = []
        /// The last read or delete started, which the next waits for.
        private var work: Task<Void, Never>?

        /// - Parameter jar: The cookie stores to read and delete from.
        nonisolated init(jar: any CookieJar = _CookieJar()) {
            self.jar = jar
        }

        public var snapshot: CookiesSnapshot {
            CookiesSnapshot(contents: contents, filter: filter)
        }

        public func perform(_ command: CookiesCommand) {
            switch command.action {
            case .reload:
                enqueue { model in await model.reload() }
            case let .setFilter(filter):
                self.filter = filter
            case let .delete(id):
                enqueue { model in await model.delete([id]) }
            case .deleteShown:
                // The cookies shown now, as the user saw them when asking, not when the work runs.
                let shown = snapshot.shownCookies.map(\.id)
                enqueue { model in await model.delete(shown) }
            }
        }

        /// Counts `drawer` as one the plugin is installed in; nothing is read until it is shown.
        func install(in drawer: ObjectIdentifier) {
            installations.insert(drawer)
        }

        /// Uncounts `drawer`; once no drawer holds the plugin, drops the cookies read, so the next
        /// show reads the stores again. The filter, and the stores' cookies, stay.
        func uninstall(from drawer: ObjectIdentifier) {
            guard installations.remove(drawer) != nil, installations.isEmpty else { return }
            contents = .unread
        }

        /// Starts `body` once the work started before it is done.
        private func enqueue(_ body: @escaping @MainActor (CookiesModel) async -> Void) {
            work = Task { [previous = work] in
                await previous?.value
                await body(self)
            }
        }

        private func reload() async {
            contents = await .cookies(jar.cookies().sortedForDisplay())
        }

        private func delete(_ ids: [StoredCookieID]) async {
            for id in ids {
                await jar.delete(id)
            }
            await reload()
        }
    }
#else
    // The release stand-in: the same members, and nothing behind them.

    /// Release builds read no cookies: this stand-in's snapshot holds nothing, and it ignores
    /// every command.
    @MainActor
    public final class CookiesModel: DebugDrawerPluginModel {
        /// The stand-in model.
        public static let shared = CookiesModel()

        private init() {}

        /// Always empty.
        public var snapshot: CookiesSnapshot {
            CookiesSnapshot()
        }

        /// Does nothing.
        ///
        /// - Parameter command: Ignored.
        public func perform(_ command: CookiesCommand) {}
    }
#endif
