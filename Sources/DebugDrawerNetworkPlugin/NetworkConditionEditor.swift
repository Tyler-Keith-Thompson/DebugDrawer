#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// A conditioning profile's fields: its name and switch; the hosts it applies to; and what it
    /// does (the latency, the bandwidth cap, and the share of requests that fail and how), which a
    /// preset can fill. A field that can't be saved says why below it, and Save waits until none
    /// does.
    ///
    /// It keeps the draft; the caller saves the profile.
    struct NetworkConditionEditor: View {
        @State var draft: NetworkConditionDraft
        let cancel: () -> Void
        let save: (NetworkConditionProfile) -> Void
        let inspection = Inspection<Self>()

        /// - Parameters:
        ///   - draft: The fields to start from.
        ///   - cancel: Leaves without saving.
        ///   - save: Saves the profile the fields describe.
        init(draft: NetworkConditionDraft, cancel: @escaping () -> Void, save: @escaping (NetworkConditionProfile) -> Void) {
            _draft = State(initialValue: draft)
            self.cancel = cancel
            self.save = save
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                DebugDrawerSection(draft.isNew ? "New Condition" : "Edit Condition") {
                    NetworkEditorField("Name") {
                        TextField("Name", text: $draft.name, prompt: Text("Host and effect"))
                            .debugDrawerTextFieldStyle()
                            .accessibilityLabel("Name")
                    }
                    DebugDrawerRow("On", isOn: $draft.isEnabled)
                }
                DebugDrawerSection("Hosts") {
                    NetworkEditorField("Host", problem: draft.hostProblem) {
                        NetworkEditorChoice("Host match", selection: $draft.hostKind) { $0 == .any ? "All" : $0.rawValue }
                        if draft.hostKind != .any {
                            TextField("Host", text: $draft.host, prompt: Text("api.example.com"))
                                .debugDrawerFont(.code)
                                .debugDrawerTextFieldStyle()
                                .autocorrectionDisabled()
                                .accessibilityLabel("Host")
                            #if os(iOS)
                                .textInputAutocapitalization(.never)
                                .keyboardType(.URL)
                            #endif
                        }
                    }
                } footer: {
                    Text("A pattern matches the whole host, without regard to case; in a wildcard, * matches within one label and ** across them.")
                }
                DebugDrawerSection("Effect") {
                    NetworkEditorField("Preset") { presets }
                    number("Latency", unit: "ms", text: $draft.latency, prompt: "0", problem: draft.latencyProblem)
                    number("Bandwidth", unit: "KB/s", text: $draft.bandwidth, prompt: "No cap", problem: draft.bandwidthProblem)
                    number("Failure Rate", unit: "%", text: $draft.failureRate, prompt: "0", problem: draft.failureRateProblem)
                    NetworkEditorField("Failure") {
                        NetworkEditorChoice("Failure", selection: $draft.failure) { $0.title }
                    }
                } footer: {
                    Text("A request waits out the latency first; then it fails, or its answer, mocked or real, arrives no faster than the bandwidth.")
                }
                DebugDrawerActionRow {
                    Button("Save") {
                        if let profile = draft.profile { save(profile) }
                    }
                    .debugDrawerButtonStyle(.primary)
                    .disabled(draft.profile == nil)
                    .accessibilityLabel("Save the condition")
                    Button("Cancel", action: cancel)
                        .accessibilityLabel("Cancel editing the condition")
                }
            }
            .onReceive(inspection.notice) { inspection.visit(self, $0) }
        }

        private var presets: some View {
            Menu {
                ForEach(NetworkConditionPreset.all) { preset in
                    Button(preset.name) { draft.apply(preset) }
                        .accessibilityLabel(preset.name)
                }
            } label: {
                Text("Fill from a Preset")
            }
            .fixedSize()
            .accessibilityLabel("Fill from a preset")
        }

        /// A number's field: its text field and, after it, the unit.
        private func number(_ title: String, unit: String, text: Binding<String>, prompt: String, problem: String?) -> some View {
            NetworkEditorField(title, problem: problem) {
                HStack(alignment: .firstTextBaseline) {
                    TextField(title, text: text, prompt: Text(prompt))
                        .debugDrawerFont(.value)
                        .debugDrawerTextFieldStyle()
                        .accessibilityLabel("\(title) in \(unit)")
                    #if os(iOS)
                        .keyboardType(unit == "KB/s" ? .decimalPad : .numberPad)
                    #endif
                    Text(unit)
                        .debugDrawerFont(.value)
                        .debugDrawerForegroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    extension NetworkConditionProfile.Failure: Identifiable {
        /// The failure itself.
        public var id: Self {
            self
        }
    }
#endif
