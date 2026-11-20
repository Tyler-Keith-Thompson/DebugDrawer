#if DEBUG
    import DebugDrawer
    import DebugDrawerNotifications
    import SwiftUI

    /// An editor for an APNs payload, checked as it is typed, a delay, and Send, which delivers it
    /// as a local notification; under it what is wrong with it, what a local notification does
    /// differently, and how the last send went.
    struct PayloadComposer: View {
        @Binding var draft: String
        @Binding var delay: SendDelay
        let sendState: SendState
        let authorization: NotificationSettings.Authorization
        let onSend: () -> Void
        @ScaledMetric(relativeTo: .body) private var editorHeight: CGFloat = 110
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        var body: some View {
            let parsed = Result { () throws(NotificationPayloadError) in try NotificationPayload(parsing: draft) }
            DebugDrawerSection("Send a payload") {
                DebugDrawerCodeBlock {
                    TextEditor(text: $draft)
                        .autocorrectionDisabled()
                        .frame(height: editorHeight)
                        .scrollContentBackground(.hidden)
                        .accessibilityLabel("APNs payload")
                        .accessibilityHint("A JSON object with an aps dictionary")
                    #if os(iOS)
                        .textInputAutocapitalization(.never)
                    #endif
                }
                messages(parsed)
                controls(canSend: (try? parsed.get()) != nil && sendState != .sending)
                outcome
            } footer: {
                Text("""
                The whole payload becomes the notification's userInfo. While the app is in front, the system shows it only if \
                the app's notification center delegate asks for a banner in userNotificationCenter(_:willPresent:).
                """)
            }
        }

        /// What is wrong with the draft, or the notes on how a local notification differs.
        @ViewBuilder
        private func messages(_ parsed: Result<NotificationPayload, NotificationPayloadError>) -> some View {
            switch parsed {
            case let .failure(error):
                DebugDrawerIssueRow(error.message, severity: .error)
            case let .success(payload):
                ForEach(payload.notes, id: \.self) { note in
                    DebugDrawerIssueRow(note, severity: .warning)
                }
            }
            if authorization == .denied {
                DebugDrawerIssueRow("Notifications are denied: the system accepts what is sent and shows nothing.", severity: .warning)
            }
        }

        /// The delays side by side, or, at accessibility text sizes, where a segmented control's
        /// titles don't grow, in a menu.
        @ViewBuilder private var delayPicker: some View {
            let picker = Picker("Deliver", selection: $delay) {
                ForEach(SendDelay.allCases) { delay in
                    Text(delay.title).tag(delay)
                }
            }
            if dynamicTypeSize.isAccessibilitySize {
                picker.pickerStyle(.menu)
            } else {
                picker.pickerStyle(.segmented)
            }
        }

        /// The delay and Send, in an action row that stacks them at accessibility text sizes.
        private func controls(canSend: Bool) -> some View {
            DebugDrawerActionRow {
                delayPicker
                    .labelsHidden()
                    .fixedSize()
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("When to deliver")
                Button(authorization == .notDetermined ? "Ask and Send" : "Send", action: onSend)
                    .debugDrawerButtonStyle(.primary)
                    .disabled(!canSend)
                    .accessibilityLabel("Send the payload as a local notification")
            }
        }

        @ViewBuilder private var outcome: some View {
            switch sendState {
            case .idle:
                EmptyView()
            case .sending:
                Text("Sending…")
                    .debugDrawerFont(.secondary)
                    .debugDrawerForegroundStyle(.secondary)
            case let .sent(identifier, delay):
                DebugDrawerIssueRow(
                    delay == .now ? "Sent as \(identifier)." : "Sent as \(identifier), to arrive \(delay.title.lowercased()).",
                    severity: .ok
                )
            case let .failed(message):
                DebugDrawerIssueRow("The system refused it: \(message)", severity: .error)
            }
        }
    }
#endif
