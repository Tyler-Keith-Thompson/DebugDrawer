#if DEBUG
    import DebugDrawer
    import SwiftUI
    import UniformTypeIdentifiers

    /// A mock rule's fields: its name and switch; the request it matches (methods, host, path and
    /// query); and the response (status, content type, headers and body, as text or a file). A
    /// field that can't be saved says why below it, and Save waits until none does.
    ///
    /// It keeps the draft and whether the file importer is open; the caller saves the rule.
    struct NetworkMockEditor: View {
        @State var draft: NetworkMockDraft
        /// Copies a chosen file into the storage and returns its name; `nil` when it can't.
        let importBody: (URL) -> String?
        let cancel: () -> Void
        let save: (NetworkMockRule) -> Void
        @State var isImporting = false
        @ScaledMetric(relativeTo: .body) private var bodyHeight: CGFloat = 140
        @ScaledMetric(relativeTo: .body) private var padding: CGFloat = 4
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize
        let inspection = Inspection<Self>()

        /// - Parameters:
        ///   - draft: The fields to start from.
        ///   - importBody: Copies a chosen file into the storage and returns its name.
        ///   - cancel: Leaves without saving.
        ///   - save: Saves the rule the fields describe.
        init(
            draft: NetworkMockDraft,
            importBody: @escaping (URL) -> String?,
            cancel: @escaping () -> Void,
            save: @escaping (NetworkMockRule) -> Void
        ) {
            _draft = State(initialValue: draft)
            self.importBody = importBody
            self.cancel = cancel
            self.save = save
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                DebugDrawerSection(draft.isNew ? "New Mock" : "Edit Mock") {
                    field("Name") {
                        TextField("Name", text: $draft.name, prompt: Text("Method and pattern"))
                            .debugDrawerTextFieldStyle()
                            .accessibilityLabel("Name")
                    }
                    DebugDrawerRow("On", isOn: $draft.isEnabled)
                }
                DebugDrawerSection("Request") {
                    field("Methods") { methods }
                    patternField("Host", kind: $draft.hostKind, text: $draft.host, prompt: "*.example.com", problem: draft.hostProblem)
                    patternField("Path", kind: $draft.pathKind, text: $draft.path, prompt: "/v1/users/*", problem: draft.pathProblem)
                    fieldList("Query", noun: "query item", fields: $draft.query)
                } footer: {
                    Text("In a wildcard, * matches within one label or segment and ** across them. A pattern matches the whole host or path.")
                }
                DebugDrawerSection("Response") {
                    field("Status", problem: draft.statusProblem) {
                        TextField("Status", text: $draft.status, prompt: Text("200"))
                            .debugDrawerFont(.value)
                            .debugDrawerTextFieldStyle()
                            .accessibilityLabel("Status")
                        #if os(iOS)
                            .keyboardType(.numberPad)
                        #endif
                    }
                    field("Content Type") {
                        TextField("Content Type", text: $draft.contentType, prompt: Text("From the headers"))
                            .debugDrawerFont(.code)
                            .debugDrawerTextFieldStyle()
                            .accessibilityLabel("Content Type")
                            .autocorrectionDisabled()
                    }
                    fieldList("Headers", noun: "header", fields: $draft.headers)
                    field("Body", problem: draft.bodyProblem) { responseBody }
                }
                DebugDrawerActionRow {
                    Button("Save") {
                        if let rule = draft.rule { save(rule) }
                    }
                    .debugDrawerButtonStyle(.primary)
                    .disabled(draft.rule == nil)
                    .accessibilityLabel("Save the mock")
                    Button("Cancel", action: cancel)
                        .accessibilityLabel("Cancel editing the mock")
                }
            }
            .fileImporter(isPresented: $isImporting, allowedContentTypes: [.data]) { result in
                if case let .success(url) = result, let name = importBody(url) {
                    draft.bodyFile = name
                }
            }
            .onReceive(inspection.notice) { inspection.visit(self, $0) }
        }

        // MARK: Request

        private var methods: some View {
            Menu {
                Button("Any Method") { draft.methods = [] }
                Divider()
                ForEach(NetworkMockDraft.standardMethods, id: \.self) { method in
                    Toggle(method, isOn: Binding(
                        get: { draft.methods.contains(method) },
                        set: { isOn in
                            if isOn { draft.methods.insert(method) } else { draft.methods.remove(method) }
                        }
                    ))
                    .accessibilityLabel(method)
                }
            } label: {
                Text(draft.methods.isEmpty ? "Any" : draft.methods.sorted().joined(separator: ", "))
                    .debugDrawerFont(.code)
            }
            .fixedSize()
            .accessibilityLabel("Methods")
            .accessibilityValue(draft.methods.isEmpty ? "Any" : draft.methods.sorted().joined(separator: ", "))
        }

        private func patternField(
            _ title: String,
            kind: Binding<NetworkMockDraft.PatternKind>,
            text: Binding<String>,
            prompt: String,
            problem: String?
        ) -> some View {
            field(title, problem: problem) {
                choice("\(title) match", selection: kind)
                if kind.wrappedValue != .any {
                    TextField(title, text: text, prompt: Text(prompt))
                        .debugDrawerFont(.code)
                        .debugDrawerTextFieldStyle()
                        .autocorrectionDisabled()
                        .accessibilityLabel(title)
                    #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    #endif
                }
            }
        }

        // MARK: Response

        @ViewBuilder private var responseBody: some View {
            choice("Body", selection: $draft.bodyKind)
            switch draft.bodyKind {
            case .empty:
                EmptyView()
            case .text:
                TextEditor(text: $draft.bodyText)
                    .debugDrawerFont(.code)
                    .autocorrectionDisabled()
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: bodyHeight)
                    .padding(padding)
                    .overlay {
                        RoundedRectangle(cornerRadius: 4).strokeBorder(.separator)
                    }
                    .accessibilityLabel("Body text")
                #if os(iOS)
                    .textInputAutocapitalization(.never)
                #endif
            case .file:
                DebugDrawerActionRow {
                    Button(draft.bodyFile == nil ? "Choose File…" : "Replace File…") { isImporting = true }
                        .accessibilityLabel(draft.bodyFile == nil ? "Choose a file for the body" : "Replace the body's file")
                }
                if let file = draft.bodyFile {
                    DebugDrawerCodeText(file)
                        .debugDrawerForegroundStyle(.secondary)
                }
            }
        }

        // MARK: Layout

        /// A choice of a few words: segments, or at accessibility text sizes, where the segments
        /// would shrink their words past reading, a menu.
        @ViewBuilder
        private func choice<Choice>(_ title: String, selection: Binding<Choice>) -> some View
            where Choice: CaseIterable & Identifiable & Hashable & RawRepresentable,
            Choice.AllCases: RandomAccessCollection, Choice.RawValue == String {
            let picker = Picker(title, selection: selection) {
                ForEach(Choice.allCases) { Text($0.rawValue).tag($0) }
            }
            .labelsHidden()
            .accessibilityLabel(title)
            if dynamicTypeSize.isAccessibilitySize {
                picker
                    .pickerStyle(.menu)
                    .fixedSize()
            } else {
                picker
                    .pickerStyle(.segmented)
                    .accessibilityElement(children: .contain)
            }
        }

        /// A field's name above its control, and the problem with it, if any, below.
        private func field(_ title: String, problem: String? = nil, @ViewBuilder content: () -> some View) -> some View {
            VStack(alignment: .leading, spacing: padding) {
                Text(title)
                    .debugDrawerFont(.label)
                    .debugDrawerForegroundStyle(.secondary)
                    .accessibilityHidden(true)
                content()
                if let problem {
                    HStack(alignment: .firstTextBaseline, spacing: padding) {
                        DebugDrawerIssueGlyph(.error)
                            .accessibilityHidden(true)
                        Text(problem)
                            .debugDrawerFont(.secondary)
                            .debugDrawerForegroundStyle(.error)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, padding)
        }

        /// Name and value rows with a remove button each, then a button that adds one.
        private func fieldList(_ title: String, noun: String, fields: Binding<[NetworkMockDraft.Field]>) -> some View {
            field(title) {
                ForEach(fields) { $item in
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
                            TextField("Value", text: $item.value)
                                .debugDrawerFont(.code)
                                .debugDrawerTextFieldStyle()
                                .autocorrectionDisabled()
                                .accessibilityLabel("\(noun.capitalized) value")
                        }
                        Button {
                            fields.wrappedValue.removeAll { $0.id == item.id }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .debugDrawerButtonStyle(.borderless)
                        .accessibilityLabel("Remove \(noun) \(item.name)")
                    }
                }
                DebugDrawerActionRow {
                    Button("Add \(noun.capitalized)") { fields.wrappedValue.append(NetworkMockDraft.Field()) }
                        .accessibilityLabel("Add \(noun)")
                }
            }
        }
    }
#endif
