#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// An open keychain item: a password's value, masked while the rules call it sensitive until
    /// revealed, then every documented attribute the keychain returned by name, the rest under a
    /// collapsed Other attributes, and the actions: Edit for a generic
    /// password, Copy (the value or the attributes), and Delete, which asks first.
    struct KeychainItemDetail: View {
        let selection: KeychainSelection
        let redaction: DebugDrawerRedaction
        var onEdit: (() -> Void)?
        let onDelete: () -> Void
        @State private var isConfirmingDelete = false
        @State private var isShowingOther = false

        private var item: KeychainItem {
            selection.item
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                if item.itemClass.holdsPassword {
                    value
                }

                Group {
                    ForEach(item.attributes.filter(\.isDocumented), id: \.key) { attribute in
                        DebugDrawerKeyValueRow(attribute.name, value: attribute.value, labelWidth: 96)
                    }
                    if !otherAttributes.isEmpty {
                        other
                    }
                }
                // Attributes are identifiers, dates and flags, read as data.
                .debugDrawerValueStyle(.code)

                DebugDrawerActionRow {
                    actions
                } trailing: {
                    if isConfirmingDelete {
                        confirmation
                    } else {
                        Button("Delete", role: .destructive) { isConfirmingDelete = true }
                            .debugDrawerButtonStyle(.destructive)
                            .accessibilityLabel("Delete \(item.title)")
                    }
                }
            }
            .padding(.bottom, 4)
        }

        private var otherAttributes: [KeychainAttribute] {
            item.attributes.filter { !$0.isDocumented }
        }

        // The keychain's own bookkeeping (`sha1`, `tomb`, `musr`) has no public name, so it keeps
        // its raw key, out of the way until asked for.
        private var other: some View {
            DisclosureGroup(isExpanded: $isShowingOther) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(otherAttributes, id: \.key) { attribute in
                        DebugDrawerKeyValueRow(attribute.name, value: attribute.value, labelWidth: 96)
                    }
                }
            } label: {
                Text("Other attributes")
                    .debugDrawerFont(.label)
                    .debugDrawerForegroundStyle(.secondary)
            }
            .accessibilityHint("Shows the attributes without a public name, by their raw keys")
        }

        @ViewBuilder private var value: some View {
            switch selection.value {
            case let .success(data):
                let preview = data.map(\.keychainPreview) ?? "<no data>"
                DebugDrawerCodeBlock {
                    RedactedText(preview, redacted: item.isSensitive(under: redaction) ? DebugDrawerRedaction.mask : preview)
                }
            case let .failure(error):
                DebugDrawerIssueRow("Value unreadable", severity: .error) {
                    Text(error.message)
                }
            }
        }

        // Edit, a Copy menu (the value and the attributes) and Delete fit on one line in a 316-point
        // drawer on iOS, where Edit, Copy Value, a menu and Delete wrapped. A certificate or key has
        // only its attributes to copy, so its button copies them directly.
        @ViewBuilder private var actions: some View {
            if let onEdit {
                Button("Edit…", action: onEdit)
                    .accessibilityLabel("Edit…")
                    .accessibilityHint("Opens a form to edit \(item.title)")
            }
            if item.itemClass.holdsPassword {
                Menu("Copy") {
                    Button("Copy Value") {
                        if let value = selection.copiedValue(redaction: redaction) { debugDrawerCopyToClipboard(value) }
                    }
                    .disabled(selection.copiedValue(redaction: redaction) == nil)
                    Button("Copy Attributes") { debugDrawerCopyToClipboard(item.attributesText) }
                }
                .menuStyle(.button)
                .fixedSize()
                .accessibilityLabel("Copy from \(item.title)")
            } else {
                DebugDrawerCopyButton("Copy Attributes") { item.attributesText }
            }
        }

        private var confirmation: some View {
            HStack {
                Text("Sure?")
                    .debugDrawerFont(.body)
                    .debugDrawerForegroundStyle(.error)
                Button("Cancel") { isConfirmingDelete = false }
                    .debugDrawerButtonStyle(.secondary)
                Button("Delete", role: .destructive) {
                    isConfirmingDelete = false
                    onDelete()
                }
                .debugDrawerButtonStyle(.destructive)
                .accessibilityLabel("Delete \(item.title)")
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Delete \(item.title)?")
        }
    }

    extension KeychainSelection {
        /// What Copy Value puts on the clipboard: the value as UTF-8 text, or the mask when the
        /// item is sensitive; `nil` when there is no value or it isn't text.
        func copiedValue(redaction: DebugDrawerRedaction) -> String? {
            guard case let .success(data?) = value, let text = String(data: data, encoding: .utf8) else { return nil }
            return item.isSensitive(under: redaction) ? DebugDrawerRedaction.mask : text
        }
    }

    extension KeychainItem {
        /// Each attribute on a line of its own, "Name: value", as Copy Attributes copies them.
        var attributesText: String {
            attributes.map { "\($0.name): \($0.value)" }.joined(separator: "\n")
        }
    }

    extension Data {
        /// A password as the detail shows it: its text, cut at 200 characters, or its size when it
        /// isn't text.
        fileprivate var keychainPreview: String {
            guard let text = String(data: self, encoding: .utf8) else { return "<\(count) bytes>" }
            return text.count > 200 ? String(text.prefix(200)) + "..." : text
        }
    }
#endif
