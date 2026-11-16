#if DEBUG
    import DebugDrawer
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
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize
        @ScaledMetric(relativeTo: .caption2) private var editorHeight: CGFloat = 110

        var body: some View {
            let parsed = Result { () throws(NotificationPayloadError) in try NotificationPayload(parsing: draft) }
            VStack(alignment: .leading, spacing: 6) {
                NotificationsSectionHeading(title: "Send a Payload")
                TextEditor(text: $draft)
                    .font(.system(.caption2, design: .monospaced))
                    .autocorrectionDisabled()
                    .frame(height: editorHeight)
                    .scrollContentBackground(.hidden)
                    .padding(4)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 4))
                    .accessibilityLabel("APNs payload")
                    .accessibilityHint("A JSON object with an aps dictionary")
                    #if os(iOS)
                        .textInputAutocapitalization(.never)
                    #endif
                messages(parsed)
                controls(canSend: (try? parsed.get()) != nil && sendState != .sending)
                outcome
                Text("""
                The whole payload becomes the notification's userInfo. While the app is in front, the system shows it only if \
                the app's notification center delegate asks for a banner in userNotificationCenter(_:willPresent:).
                """)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }

        /// What is wrong with the draft, or the notes on how a local notification differs.
        @ViewBuilder
        private func messages(_ parsed: Result<NotificationPayload, NotificationPayloadError>) -> some View {
            switch parsed {
            case let .failure(error):
                Label {
                    Text(error.message)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "xmark.octagon.fill")
                        .accessibilityHidden(true)
                }
                .font(.caption)
                .foregroundStyle(.red)
            case let .success(payload):
                ForEach(payload.notes, id: \.self) { note in
                    Text(note)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if authorization == .denied {
                Text("Notifications are denied: the system accepts what is sent and shows nothing.")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        /// The delay and Send: side by side, or one above the other at accessibility text sizes.
        private func controls(canSend: Bool) -> some View {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                : AnyLayout(HStackLayout())
            return layout {
                Picker("Deliver", selection: $delay) {
                    ForEach(SendDelay.allCases) { delay in
                        Text(delay.title).tag(delay)
                    }
                }
                .pickerStyle(.segmented)
                .controlSize(.small)
                .labelsHidden()
                .fixedSize()
                .accessibilityElement(children: .contain)
                .accessibilityLabel("When to deliver")
                Button(authorization == .notDetermined ? "Ask and Send" : "Send", action: onSend)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
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
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            case let .sent(identifier, delay):
                Text(delay == .now ? "Sent as \(identifier)." : "Sent as \(identifier), to arrive \(delay.title.lowercased()).")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            case let .failed(message):
                Text("The system refused it: \(message)")
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
#endif
