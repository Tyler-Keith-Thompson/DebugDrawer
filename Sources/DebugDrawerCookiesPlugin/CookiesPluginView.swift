#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// The plugin's body: the toolbar, the filter and the cookies it shows. Reads the stores each
    /// time it appears.
    ///
    /// It draws ``CookiesModel``'s snapshots from its transport and sends it what the user does;
    /// Copy, which writes the clipboard, stays here. What it shows and copies is masked by the
    /// redaction rules of the drawer it is shown in, followed as they change.
    struct CookiesPluginView: View {
        @StateObject private var transport: DebugDrawerPluginTransport<CookiesSnapshot, CookiesCommand>
        /// The drawer the plugin is shown in; `nil` outside any drawer.
        @Environment(\.showingDrawer) private var showingDrawer
        // Kept by cookie, not by position, so a row deleted above another doesn't pass its
        // expanded state on.
        @State var expanded: Set<StoredCookie.ID> = []
        /// The tallest the list grows before it scrolls; scales with Dynamic Type, as its rows do.
        @ScaledMetric(relativeTo: .body) private var listHeight: CGFloat = 300
        let inspection = Inspection<Self>() // from/for ViewInspector.

        /// - Parameter transport: Joins the view to the model; made once, for the view's lifetime.
        init(transport: @escaping @autoclosure () -> DebugDrawerPluginTransport<CookiesSnapshot, CookiesCommand>) {
            _transport = StateObject(wrappedValue: transport())
        }

        var body: some View {
            DebugDrawerRedactionReader(showingDrawer) { redaction in
                content(redaction: redaction)
            }
            .onAppear { transport.send(CookiesCommand(.reload)) }
            .onReceive(inspection.notice) { inspection.visit(self, $0) }
        }

        /// The toolbar, the filter and the cookies, masked by `redaction`.
        private func content(redaction: DebugDrawerRedaction) -> some View {
            let snapshot = transport.snapshot
            return VStack(alignment: .leading, spacing: 6) {
                CookiesToolbar(
                    count: snapshot.count,
                    refresh: { transport.send(CookiesCommand(.reload)) },
                    deleteAll: { transport.send(CookiesCommand(.deleteShown)) },
                    copy: { debugDrawerCopyToClipboard(transport.snapshot.shownCookies.report(redaction: redaction)) }
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
                                    stored: stored, redaction: redaction, isExpanded: expanded.contains(stored.id),
                                    toggle: { toggle(stored.id) },
                                    onDelete: { transport.send(CookiesCommand(.delete(stored.id))) }
                                )
                            }
                        }
                    }
                    .frame(maxHeight: listHeight)
                }
            }
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
