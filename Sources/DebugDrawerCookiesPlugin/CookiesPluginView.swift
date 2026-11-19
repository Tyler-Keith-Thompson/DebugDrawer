#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// The plugin's body: the toolbar, the filter and the cookies it shows. Reads the stores each
    /// time it appears.
    ///
    /// It draws ``CookiesModel``'s snapshots from its transport and sends it what the user does;
    /// Copy, which writes the clipboard, stays here.
    struct CookiesPluginView: View {
        @StateObject private var transport: DebugDrawerPluginTransport<CookiesSnapshot, CookiesCommand>
        @ObservedObject private var drawer = DebugDrawer.shared
        // Kept by cookie, not by position, so a row deleted above another doesn't pass its
        // expanded state on.
        @State var expanded: Set<StoredCookie.ID> = []
        let inspection = Inspection<Self>() // from/for ViewInspector.

        /// - Parameter transport: Joins the view to the model; made once, for the view's lifetime.
        init(transport: @escaping @autoclosure () -> DebugDrawerPluginTransport<CookiesSnapshot, CookiesCommand>) {
            _transport = StateObject(wrappedValue: transport())
        }

        var body: some View {
            let snapshot = transport.snapshot
            VStack(alignment: .leading, spacing: 6) {
                CookiesToolbar(
                    count: snapshot.count,
                    refresh: { transport.send(CookiesCommand(.reload)) },
                    deleteAll: { transport.send(CookiesCommand(.deleteShown)) },
                    copy: { debugDrawerCopyToClipboard(transport.snapshot.shownCookies.report(redaction: drawer.redaction)) }
                )

                TextField("Filter by name or domain...", text: filter)
                    .debugDrawerTextFieldStyle()
                    .accessibilityLabel("Filter cookies by name or domain")

                let shown = snapshot.shownCookies
                if shown.isEmpty {
                    Text(snapshot.allCookies.isEmpty ? "No cookies stored" : "No matches")
                        .debugDrawerFont(.secondary)
                        .debugDrawerForegroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(shown) { stored in
                                CookieRow(
                                    stored: stored, redaction: drawer.redaction, isExpanded: expanded.contains(stored.id),
                                    toggle: { toggle(stored.id) },
                                    onDelete: { transport.send(CookiesCommand(.delete(stored.id))) }
                                )
                            }
                        }
                    }
                    .frame(maxHeight: 300)
                }
            }
            .onAppear { transport.send(CookiesCommand(.reload)) }
            .onReceive(inspection.notice) { inspection.visit(self, $0) }
        }

        /// The filter, read from the snapshot and changed through the model.
        private var filter: Binding<String> {
            Binding(
                get: { transport.snapshot.filter },
                set: { transport.send(CookiesCommand(.setFilter($0))) }
            )
        }

        private func toggle(_ id: StoredCookie.ID) {
            if expanded.contains(id) {
                expanded.remove(id)
            } else {
                expanded.insert(id)
            }
        }
    }
#endif
