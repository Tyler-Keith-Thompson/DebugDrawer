#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// The plugin's body: draws ``UserDefaultsModel``'s snapshots from its transport through
    /// `UserDefaultsBrowserView`, and sends it what the user does; while shown, the list follows
    /// the app's writes. Copy Value, which writes the clipboard, stays in the rows. Values are
    /// masked by the redaction rules of the drawer it is shown in, followed as they change.
    struct UserDefaultsPluginView: View {
        @StateObject private var transport: DebugDrawerPluginTransport<UserDefaultsSnapshot, UserDefaultsCommand>
        /// The drawer the plugin is shown in; `nil` outside any drawer.
        @Environment(\.showingDrawer) private var showingDrawer
        let inspection = Inspection<Self>() // from/for ViewInspector.

        /// - Parameter transport: Joins the view to the model; made once, for the view's lifetime.
        init(transport: @escaping @autoclosure () -> DebugDrawerPluginTransport<UserDefaultsSnapshot, UserDefaultsCommand>) {
            _transport = StateObject(wrappedValue: transport())
        }

        var body: some View {
            let snapshot = transport.snapshot
            DebugDrawerRedactionReader(showingDrawer) { redaction in
                browser(snapshot, redaction: redaction)
            }
            .onAppear { transport.send(UserDefaultsCommand(.startObserving)) }
            .onDisappear { transport.send(UserDefaultsCommand(.stopObserving)) }
            .onReceive(inspection.notice) { inspection.visit(self, $0) }
        }

        /// The browser over `snapshot`, its values masked by `redaction`.
        private func browser(_ snapshot: UserDefaultsSnapshot, redaction: DebugDrawerRedaction) -> some View {
            UserDefaultsBrowserView(
                suites: snapshot.suites,
                selectedSuite: binding(\.selectedSuite) { .selectSuite($0) },
                entries: snapshot.filteredEntries,
                keys: snapshot.persistentKeys,
                searchText: binding(\.searchText) { .setSearchText($0) },
                showOtherDomains: binding(\.showOtherDomains) { .setShowOtherDomains($0) },
                redaction: redaction,
                actions: UserDefaultsBrowserActions(
                    set: { transport.send(UserDefaultsCommand(.set($0, forKey: $1))) },
                    add: { transport.send(UserDefaultsCommand(.add($0, type: $1))) },
                    remove: { transport.send(UserDefaultsCommand(.remove($0))) },
                    reload: { transport.send(UserDefaultsCommand(.reload)) }
                )
            )
        }

        /// A value read from the snapshot and changed through the model.
        private func binding<Value>(
            _ keyPath: KeyPath<UserDefaultsSnapshot, Value>,
            _ command: @escaping (Value) -> UserDefaultsCommand.Action
        ) -> Binding<Value> {
            Binding(
                get: { transport.snapshot[keyPath: keyPath] },
                set: { transport.send(UserDefaultsCommand(command($0))) }
            )
        }
    }

    /// The header's readout ("12 keys"): reads the model's snapshot, and follows the app's writes
    /// while shown, which it is while the plugin is closed too.
    struct UserDefaultsHeaderAccessory: View {
        @StateObject private var transport: DebugDrawerPluginTransport<UserDefaultsSnapshot, UserDefaultsCommand>

        /// - Parameter transport: Joins the view to the model; made once, for the view's lifetime.
        init(transport: @escaping @autoclosure () -> DebugDrawerPluginTransport<UserDefaultsSnapshot, UserDefaultsCommand>) {
            _transport = StateObject(wrappedValue: transport())
        }

        var body: some View {
            let count = transport.snapshot.filteredEntries.count
            Text(count == 1 ? "1 key" : "\(count.formatted()) keys")
                .onAppear { transport.send(UserDefaultsCommand(.startObserving)) }
                .onDisappear { transport.send(UserDefaultsCommand(.stopObserving)) }
        }
    }
#endif
