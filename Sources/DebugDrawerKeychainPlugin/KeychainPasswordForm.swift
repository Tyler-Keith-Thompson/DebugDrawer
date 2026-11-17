#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// The form that adds a generic password, or edits one: its service, account, label, password
    /// (hidden until revealed), access group and accessibility, with Save and Cancel. An edit
    /// leaves the item in its access group, which the form shows.
    struct KeychainPasswordForm: View {
        let editor: KeychainEditor
        /// The groups an added password can go in, besides the app's default one.
        let accessGroups: [String]
        /// The keychain's refusal of the last save, if it refused.
        let issue: KeychainIssue?
        let save: (GenericPassword) -> Void
        let cancel: () -> Void
        @State private var draft: GenericPassword
        @State private var isValueRevealed = false
        let inspection = Inspection<Self>() // from/for ViewInspector.

        init(
            editor: KeychainEditor,
            accessGroups: [String],
            issue: KeychainIssue?,
            save: @escaping (GenericPassword) -> Void,
            cancel: @escaping () -> Void
        ) {
            self.editor = editor
            self.accessGroups = accessGroups
            self.issue = issue
            self.save = save
            self.cancel = cancel
            _draft = State(initialValue: editor.draft)
        }

        private var isAdding: Bool {
            if case .adding = editor { return true }
            return false
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                DebugDrawerSection(isAdding ? "Add password" : "Edit password") {
                    KeychainFormField("Service") { textField("Service", text: $draft.service) }
                    KeychainFormField("Account") { textField("Account", text: $draft.account) }
                    KeychainFormField("Label") { textField("Label", text: $draft.label, prompt: "Optional") }
                    KeychainFormField("Password") { passwordField }
                    accessGroup
                    KeychainFormField("Accessible") { accessibilityPicker }
                    if let issue {
                        DebugDrawerIssueRow("Keychain refused", severity: .error) {
                            Text(issue.message)
                        }
                    }
                }
                DebugDrawerActionRow {
                    Button("Save") { save(draft) }
                        .debugDrawerButtonStyle(.primary)
                        .disabled(!draft.isSavable)
                        .accessibilityLabel("Save the password")
                        .accessibilityHint("Needs a service or an account")
                    Button("Cancel", action: cancel)
                        .accessibilityLabel(isAdding ? "Cancel adding the password" : "Cancel editing the password")
                }
            }
            .onReceive(inspection.notice) { inspection.visit(self, $0) }
        }

        private func textField(_ title: String, text: Binding<String>, prompt: String? = nil) -> some View {
            TextField(title, text: text, prompt: prompt.map { Text($0) })
                .debugDrawerFont(.code)
                .debugDrawerTextFieldStyle()
                .autocorrectionDisabled()
                .accessibilityLabel(title)
                .textContentType(.oneTimeCode)
            #if os(iOS)
                .textInputAutocapitalization(.never)
            #endif
        }

        // A secure field until revealed, as the detail keeps a sensitive value masked.
        private var passwordField: some View {
            HStack(spacing: 6) {
                Group {
                    if isValueRevealed {
                        TextField("Password", text: $draft.value)
                            .accessibilityLabel("Password")
                            .textContentType(.oneTimeCode)
                    } else {
                        // An account beside a secure field reads as a sign-in form, which iOS offers
                        // to save to the user's Passwords on Save. These are the app's own keychain
                        // items, not the user's credentials, so the fields say they hold a one-time
                        // code, which AutoFill neither saves nor fills.
                        SecureField("Password", text: $draft.value)
                            .accessibilityLabel("Password")
                            .textContentType(.oneTimeCode)
                    }
                }
                .debugDrawerFont(.code)
                .debugDrawerTextFieldStyle()
                .autocorrectionDisabled()
                #if os(iOS)
                    .textInputAutocapitalization(.never)
                #endif
                Button {
                    isValueRevealed.toggle()
                } label: {
                    Image(systemName: isValueRevealed ? "eye.slash" : "eye")
                }
                .debugDrawerButtonStyle(.borderless)
                .accessibilityLabel(isValueRevealed ? "Hide password" : "Show password")
            }
        }

        @ViewBuilder private var accessGroup: some View {
            if isAdding {
                if !accessGroups.isEmpty {
                    KeychainFormField("Access group") {
                        KeychainChoiceMenu(title: "Access group", selection: $draft.accessGroup, choices: [nil] + accessGroups.map(Optional.some)) {
                            $0 ?? "Default"
                        }
                    }
                }
            } else if let group = draft.accessGroup {
                DebugDrawerKeyValueRow("Access group", value: group, labelWidth: 96)
                    .debugDrawerValueStyle(.code)
            }
        }

        private var accessibilityPicker: some View {
            KeychainChoiceMenu(title: "Accessible", selection: $draft.accessibility, choices: KeychainAccessibility.allCases, label: \.title)
        }
    }

    /// A form field: its name above its control. A copy of the Network plugin's editor field: a
    /// few lines cost less than a shared module.
    struct KeychainFormField<Content: View>: View {
        let title: String
        let content: Content
        @ScaledMetric(relativeTo: .body) private var padding: CGFloat = 4

        init(_ title: String, @ViewBuilder content: () -> Content) {
            self.title = title
            self.content = content()
        }

        var body: some View {
            VStack(alignment: .leading, spacing: padding) {
                Text(title)
                    .debugDrawerFont(.label)
                    .debugDrawerForegroundStyle(.secondary)
                    .accessibilityHidden(true)
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, padding)
        }
    }
#endif
