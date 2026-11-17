#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// A key's value edited at any depth. An array or a dictionary lists what it holds; tapping one
    /// drills into it, and Back returns. A value that holds no others shows its control. Each
    /// edit, addition or deletion, however deep, saves the whole value of the key.
    struct PropertyListEditor: View {
        /// The key the value belongs to, the first step of the path shown.
        let key: String
        /// The key's whole value.
        let value: PropertyListValue
        /// Saves the key's whole value.
        let save: (PropertyListValue) -> Void
        @State private var path: [PropertyListPathComponent] = []
        @State private var isAdding = false
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize
        @ScaledMetric(relativeTo: .body) private var indent: CGFloat = 12
        let inspection = Inspection<Self>()

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                if let node = value.value(at: path) {
                    if !path.isEmpty {
                        // A field inside names itself by the path, so the path stays above it
                        // when the keyboard scrolls the list; the trail then shows Back alone.
                        trail(showsPath: !node.isTextField)
                    }
                    switch node {
                    case .array, .dictionary:
                        container(node)
                    case .string, .number, .bool, .date, .data:
                        PropertyListScalarEditor(
                            value: node,
                            title: pathTitle,
                            deleteItem: deleteItemAction,
                            save: { save(value.replacing(at: path, with: $0)) }
                        )
                        // A fresh field for each value drilled into.
                        .id(path)
                    }
                }
            }
            // The app removed what the path led to: back to the key's value.
            .onChange(of: value) {
                if value.value(at: path) == nil { path = [] }
            }
            .onReceive(inspection.notice) { inspection.visit(self, $0) }
        }

        /// Back, and the steps to the value shown unless its field names them.
        private func trail(showsPath: Bool) -> some View {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Button {
                    path.removeLast()
                    isAdding = false
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                .debugDrawerButtonStyle(.borderless)
                .accessibilityLabel("Back")
                .accessibilityHint("Shows what holds this value")
                if showsPath {
                    Text(pathTitle)
                        .debugDrawerFont(.code)
                        .debugDrawerForegroundStyle(.secondary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                        .truncationMode(.head)
                        .help(pathTitle)
                }
            }
            .debugDrawerRowPadding()
        }

        @ViewBuilder
        private func container(_ node: PropertyListValue) -> some View {
            let children = node.children
            // Indented, so what the value holds reads as beneath its key rather than beside it.
            VStack(alignment: .leading, spacing: 0) {
                if children.isEmpty {
                    Text(node.type == .array ? "No items" : "No keys")
                        .debugDrawerFont(.secondary)
                        .debugDrawerForegroundStyle(.tertiary)
                        .debugDrawerRowPadding()
                }
                ForEach(children) { child in
                    PropertyListChildRow(child: child) {
                        path.append(child.component)
                        isAdding = false
                    }
                }
            }
            .padding(.leading, indent)
            if isAdding {
                DefaultsAddKeyForm(
                    existingKeys: node.dictionaryKeys,
                    cancel: { isAdding = false },
                    add: { key, type in
                        guard let addition = node.adding(type.initialValue(now: .now), forKey: key) else { return }
                        save(value.replacing(at: path, with: addition.container))
                        path.append(addition.component)
                        isAdding = false
                    }
                )
            } else {
                DebugDrawerActionRow {
                    Button(node.type == .array ? "Add Item" : "Add Key") { isAdding = true }
                        .accessibilityLabel(node.type == .array ? "Add Item to \(pathTitle)" : "Add Key to \(pathTitle)")
                } trailing: {
                    if !path.isEmpty {
                        Button("Delete Item", role: .destructive, action: deleteItem)
                            .debugDrawerButtonStyle(.destructive)
                            .accessibilityLabel("Delete Item \(pathTitle)")
                    }
                }
            }
        }

        /// Delete Item for a value drilled into; `nil` for the key's own value.
        private var deleteItemAction: (() -> Void)? {
            if path.isEmpty { return nil }
            return { deleteItem() }
        }

        /// Removes the value drilled into from what holds it, and shows that.
        private func deleteItem() {
            save(value.replacing(at: path, with: nil))
            path.removeLast()
        }

        /// The key and each step after it ("settings › theme › [0]").
        private var pathTitle: String {
            ([key] + path.map(\.title)).joined(separator: " › ")
        }
    }

    /// An element of an array or a value of a dictionary: its index or key, its value in one
    /// line, and a chevron, as tapping it drills in.
    struct PropertyListChildRow: View {
        let child: PropertyListChild
        let open: () -> Void
        // One line each, so a row reads as one item, except at accessibility text sizes, where
        // that would cut the words short.
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        var body: some View {
            Button(action: open) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(child.component.title)
                        .debugDrawerFont(.code)
                        .debugDrawerForegroundStyle(.primary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                        .truncationMode(.middle)
                        .layoutPriority(1)
                    Spacer(minLength: 4)
                    Text(child.value.summary)
                        .debugDrawerFont(.code)
                        .debugDrawerForegroundStyle(.secondary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                    Image(systemName: "chevron.right")
                        .imageScale(.small)
                        .debugDrawerForegroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .debugDrawerRowPadding()
                .contentShape(Rectangle())
            }
            .debugDrawerButtonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(child.component.title), \(child.value.type.title), \(child.value.summary)")
            .accessibilityHint("Shows the value to edit")
        }
    }

    extension PropertyListValue {
        /// Whether its editor is a text field: a string, a number or data.
        fileprivate var isTextField: Bool {
            switch self {
            case .string, .number, .data: true
            case .bool, .date, .array, .dictionary: false
            }
        }

        /// A dictionary's keys; `nil` for an array, whose items take none.
        fileprivate var dictionaryKeys: Set<String>? {
            if case let .dictionary(values) = self { Set(values.keys) } else { nil }
        }
    }
#endif
