#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// An editor field of name and value rows, each with a remove button, then a button that adds
    /// one. At accessibility text sizes a row's name sits above its value. The mock editor's query
    /// items and headers and the resend editor's headers use it.
    struct NetworkNameValueList: View {
        let title: String
        /// What one row is, in lowercase ("header", "query item"), for the buttons and VoiceOver.
        let noun: String
        @Binding var fields: [NetworkNameValue]
        @ScaledMetric(relativeTo: .body) private var padding: CGFloat = 4
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        /// - Parameters:
        ///   - title: The field's name.
        ///   - noun: What one row is, in lowercase.
        ///   - fields: The rows.
        init(_ title: String, noun: String, fields: Binding<[NetworkNameValue]>) {
            self.title = title
            self.noun = noun
            _fields = fields
        }

        var body: some View {
            NetworkEditorField(title) {
                ForEach($fields) { $item in
                    let layout = dynamicTypeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: padding))
                        : AnyLayout(HStackLayout(spacing: padding))
                    HStack(alignment: .center, spacing: padding) {
                        layout {
                            TextField("Name", text: $item.name)
                                .debugDrawerFont(.code)
                                .debugDrawerTextFieldStyle()
                                .autocorrectionDisabled()
                                .accessibilityLabel("\(noun.capitalized) name")
                            #if os(iOS)
                                .textInputAutocapitalization(.never)
                            #endif
                            TextField("Value", text: $item.value)
                                .debugDrawerFont(.code)
                                .debugDrawerTextFieldStyle()
                                .autocorrectionDisabled()
                                .accessibilityLabel("\(noun.capitalized) value")
                            #if os(iOS)
                                .textInputAutocapitalization(.never)
                            #endif
                        }
                        Button {
                            fields.removeAll { $0.id == item.id }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .debugDrawerButtonStyle(.borderless)
                        .accessibilityLabel("Remove \(noun) \(item.name)")
                    }
                }
                DebugDrawerActionRow {
                    Button("Add \(noun.capitalized)") { fields.append(NetworkNameValue()) }
                        .accessibilityLabel("Add \(noun)")
                }
            }
        }
    }
#endif
