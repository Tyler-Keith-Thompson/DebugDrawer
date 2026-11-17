#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// Edit and Resend: a captured request's method, URL, headers and body, to change before it is
    /// sent again. A field that can't be sent says why below it, and Send waits until none does; a
    /// request the server may act on asks first, in place.
    ///
    /// It keeps the draft and whether the question is open; the caller sends the request.
    struct NetworkReplayEditor: View {
        @State var draft: NetworkReplayDraft
        let cancel: () -> Void
        let send: (URLRequest) -> Void
        @State var isConfirming = false
        let inspection = Inspection<Self>()

        /// - Parameters:
        ///   - draft: The fields to start from.
        ///   - cancel: Leaves without sending.
        ///   - send: Sends the request the fields describe.
        init(draft: NetworkReplayDraft, cancel: @escaping () -> Void, send: @escaping (URLRequest) -> Void) {
            _draft = State(initialValue: draft)
            self.cancel = cancel
            self.send = send
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                DebugDrawerSection("Edit and Resend") {
                    NetworkEditorField("Method") { methods }
                    NetworkEditorField("URL", problem: draft.urlProblem) {
                        TextField("URL", text: $draft.url, prompt: Text("https://api.example.com/v1/users"))
                            .debugDrawerFont(.code)
                            .debugDrawerTextFieldStyle()
                            .autocorrectionDisabled()
                            .accessibilityLabel("URL")
                            .textContentType(.URL)
                        #if os(iOS)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                        #endif
                    }
                    NetworkNameValueList("Headers", noun: "header", fields: $draft.headers)
                    NetworkEditorField("Body", problem: draft.bodyProblem) { requestBody }
                } footer: {
                    Text("The request goes through the plugin like any other: mocks and conditions apply, and the log marks it Replay.")
                }
                if isConfirming {
                    NetworkResendConfirmation(method: draft.method, confirm: sendRequest) { isConfirming = false }
                } else {
                    DebugDrawerActionRow {
                        Button("Send") {
                            if draft.needsConfirmation { isConfirming = true } else { sendRequest() }
                        }
                        .debugDrawerButtonStyle(.primary)
                        .disabled(draft.request == nil)
                        .accessibilityLabel("Send the request")
                        Button("Cancel", action: cancel)
                            .accessibilityLabel("Cancel resending")
                    }
                }
            }
            .onReceive(inspection.notice) { inspection.visit(self, $0) }
        }

        private func sendRequest() {
            isConfirming = false
            if let request = draft.request { send(request) }
        }

        private var methods: some View {
            Menu {
                ForEach(draft.methods, id: \.self) { method in
                    Button(method) {
                        draft.method = method
                        // A changed method is a new question.
                        isConfirming = false
                    }
                    .accessibilityLabel(method)
                }
            } label: {
                Text(draft.method)
                    .debugDrawerFont(.code)
            }
            .fixedSize()
            .accessibilityLabel("Method")
            .accessibilityValue(draft.method)
        }

        @ViewBuilder private var requestBody: some View {
            switch draft.body {
            case .text:
                NetworkBodyTextEditor(text: Binding {
                    if case let .text(text) = draft.body { text } else { "" }
                } set: {
                    draft.body = .text($0)
                })
            case let .binary(data):
                Text("\(data.count.formatted()) bytes that aren't text, sent as captured.")
                    .debugDrawerFont(.secondary)
                    .debugDrawerForegroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                DebugDrawerActionRow {
                    Button("Remove Body") { draft.body = .text("") }
                        .accessibilityLabel("Remove Body")
                }
            }
        }
    }
#endif
