#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// What the browser does with the shown suite.
    struct UserDefaultsBrowserActions {
        /// Writes the whole value for a key.
        let set: (PropertyListValue, String) -> Void
        /// Adds a key with a value of the type.
        let add: (String, PropertyListType) -> Void
        /// Removes a key.
        let remove: (String) -> Void
        /// Reads the suite again.
        let reload: () -> Void
    }

    /// The suite picker, when the host named suites; Add Key and a menu of the rest; then the
    /// suite's keys under a filter, each selected to edit.
    struct UserDefaultsBrowserView: View {
        let suites: [UserDefaultsSuite]
        @Binding var selectedSuite: UserDefaultsSuite
        /// The keys the filters let through.
        let entries: [DefaultsEntry]
        /// The keys of the suite's persistent domain, which a new key mustn't be.
        let keys: Set<String>
        @Binding var searchText: String
        /// Whether keys only other domains hold show, read-only.
        @Binding var showOtherDomains: Bool
        let redaction: DebugDrawerRedaction
        let actions: UserDefaultsBrowserActions
        @State private var selectedKey: String?
        @State private var isAdding = false
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        let inspection = Inspection<Self>()

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                if suites.count > 1 {
                    UserDefaultsSuitePicker(suites: suites, selection: $selectedSuite)
                }
                if isAdding {
                    DefaultsAddKeyForm(
                        existingKeys: keys,
                        cancel: { isAdding = false },
                        add: { key, type in
                            actions.add(key, type)
                            isAdding = false
                            selectedKey = key
                        }
                    )
                } else {
                    toolbar
                }
                list
            }
            .onChange(of: selectedSuite) {
                selectedKey = nil
                isAdding = false
            }
            .onReceive(inspection.notice) { inspection.visit(self, $0) }
        }

        // Add Key leads, as the plugin's main action; the rest wait in a menu, so the row keeps to
        // one line in an iPad's drawer.
        private var toolbar: some View {
            DebugDrawerActionRow {
                Button("Add Key") { isAdding = true }
                    .accessibilityLabel("Add Key")
                    .accessibilityHint("Adds a key to \(selectedSuite.title)")
            } trailing: {
                Menu {
                    Toggle("Show Other Domains", isOn: $showOtherDomains)
                        .accessibilityLabel("Show Other Domains")
                        .accessibilityHint("Shows keys from launch arguments, the global domain and registered defaults, read-only")
                    Button("Reload", action: actions.reload)
                        .accessibilityLabel("Reload")
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                        .labelStyle(.iconOnly)
                }
                .menuStyle(.button)
                .menuIndicator(.hidden)
                .debugDrawerButtonStyle(.borderless)
                .fixedSize()
                .accessibilityLabel("More")
                .help("Show keys from other domains, or reload")
            }
        }

        private var list: some View {
            ScrollViewReader { proxy in
                DebugDrawerSearchableList("Filter...", text: $searchText, accessibilityLabel: "Filter keys and values") {
                    ForEach(entries) { entry in
                        DefaultsEntryRow(
                            entry: entry,
                            redaction: redaction,
                            isSelected: selectedKey == entry.key,
                            onSelect: { selectedKey = selectedKey == entry.key ? nil : entry.key },
                            onSet: { actions.set($0, entry.key) },
                            onDelete: {
                                actions.remove(entry.key)
                                selectedKey = nil
                            }
                        )
                        .id(entry.key)
                    }
                }
                .onChange(of: selectedKey) { _, newKey in
                    if let key = newKey {
                        withAnimation(reduceMotion ? nil : .default) {
                            proxy.scrollTo(key, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }
#endif
