#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// The plugin's body: the toolbar, the filter and the cookies it shows. Reads the stores each
    /// time it appears.
    struct CookiesPluginView: View {
        @ObservedObject var model: CookiesModel
        @ObservedObject private var drawer = DebugDrawer.shared
        // Kept by cookie, not by position, so a row deleted above another doesn't pass its
        // expanded state on.
        @State var expanded: Set<StoredCookie.ID> = []
        let inspection = Inspection<Self>() // from/for ViewInspector.

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                CookiesToolbar(
                    count: model.count,
                    refresh: { Task { await model.reload() } },
                    deleteAll: { Task { await model.deleteShown() } },
                    copy: { debugDrawerCopyToClipboard(model.shownCookies.report(redaction: drawer.redaction)) }
                )

                TextField("Filter by name or domain...", text: $model.filter)
                    .debugDrawerTextFieldStyle()
                    .accessibilityLabel("Filter cookies by name or domain")

                let shown = model.shownCookies
                if shown.isEmpty {
                    Text(model.allCookies.isEmpty ? "No cookies stored" : "No matches")
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
                                    onDelete: { Task { await model.delete(stored) } }
                                )
                            }
                        }
                    }
                    .frame(maxHeight: 300)
                }
            }
            .onAppear { Task { await model.reload() } }
            .onReceive(inspection.notice) { inspection.visit(self, $0) }
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
