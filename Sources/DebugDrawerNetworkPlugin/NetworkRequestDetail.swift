#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// A request in full: its URL, time, size and status, query parameters, timing, error, headers
    /// and bodies, with a button to copy it as a cURL command. Values the redaction rules call
    /// sensitive are masked in the copy, and on screen until revealed.
    ///
    /// A request a mock answered names the mock; any other offers Mock This once it is complete.
    /// Every request offers Resend and Edit and Resend; one the server may act on asks before it
    /// is sent again. A replay names its original, and a request that was resent says how often,
    /// each with a button that selects the other.
    ///
    /// It keeps whether the question before a resend is open.
    struct NetworkRequestDetail: View {
        let entry: NetworkEntry
        let redaction: DebugDrawerRedaction
        /// Opens a new mock made from the request; `nil` offers no Mock This.
        var onMock: ((NetworkEntry) -> Void)?
        /// Sends the request again, unchanged; `nil` offers no Resend.
        var onResend: ((NetworkEntry) -> Void)?
        /// Opens the request in the resend editor; `nil` offers no Edit and Resend.
        var onEditAndResend: ((NetworkEntry) -> Void)?
        /// Selects the request with the id; `nil` offers no buttons to the linked requests.
        var onShow: ((NetworkEntry.ID) -> Void)?
        /// The requests this one is linked to by replay.
        var links = NetworkReplayLinks.none
        /// Where the last resend of this request stands, if one hasn't got its answer.
        var replayStatus: NetworkReplayStatus?
        @State var isConfirming = false
        let inspection = Inspection<Self>()

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                RedactedText(entry.url, redacted: redaction.redacting(url: entry.url))
                    .debugDrawerFont(.code)
                    .debugDrawerForegroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                DebugDrawerKeyValueRow("Time", value: entry.durationLabel)
                DebugDrawerKeyValueRow("Size", value: entry.responseSizeLabel)
                if let code = entry.statusCode {
                    DebugDrawerKeyValueRow("Status", value: String(code))
                }
                if let rule = entry.mockRuleName {
                    DebugDrawerKeyValueRow("Mocked by", value: rule)
                        .debugDrawerValueStyle(.text)
                }
                if let effect = entry.conditionEffect {
                    DebugDrawerKeyValueRow("Conditioned by", value: effect.profileName)
                        .debugDrawerValueStyle(.text)
                    DebugDrawerKeyValueRow("Condition", value: effect.summary)
                        .debugDrawerValueStyle(.text)
                }
                NetworkReplayLinkRows(entry: entry, links: links, onShow: onShow)

                if let error = entry.error {
                    DebugDrawerIssueRow("Request failed", severity: .error) {
                        Text(error)
                    }
                }

                // URL query parameters
                if let urlObj = URL(string: entry.url),
                   let components = URLComponents(url: urlObj, resolvingAgainstBaseURL: false),
                   let queryItems = components.queryItems, !queryItems.isEmpty {
                    collapsibleSection("Query Parameters") {
                        ForEach(queryItems, id: \.name) { item in
                            DebugDrawerKeyValueRow(
                                item.name,
                                value: item.value ?? "",
                                redacted: redaction.redacting(item.value ?? "", forKey: item.name)
                            )
                        }
                        .debugDrawerValueStyle(.code)
                    }
                }

                if let metrics = entry.metrics {
                    collapsibleSection("Timing") {
                        NetworkTimingView(metrics: metrics)
                    }
                }

                payload

                DebugDrawerActionRow {
                    DebugDrawerCopyButton("Copy cURL") { entry.curl(redaction: redaction) }
                    if let onMock, entry.isComplete, entry.mockRuleName == nil {
                        Button("Mock This") { onMock(entry) }
                            .accessibilityLabel("Mock This")
                            .accessibilityHint("Makes a mock that answers requests like this one with its response")
                    }
                    if let onResend {
                        Button("Resend") {
                            if NetworkReplayDraft.isSafe(entry.method) { onResend(entry) } else { isConfirming = true }
                        }
                        .disabled(isConfirming || replayStatus == .sending)
                        .accessibilityLabel("Resend")
                        .accessibilityHint("Sends the request again, unchanged")
                    }
                    if let onEditAndResend {
                        Button("Edit and Resend…") { onEditAndResend(entry) }
                            .accessibilityLabel("Edit and Resend…")
                            .accessibilityHint("Opens the request to change its method, URL, headers or body before sending it again")
                    }
                }
                if isConfirming, let onResend {
                    NetworkResendConfirmation(method: entry.method) {
                        isConfirming = false
                        onResend(entry)
                    } cancel: {
                        isConfirming = false
                    }
                }
                NetworkReplayStatusRow(status: replayStatus)
            }
            .onReceive(inspection.notice) { inspection.visit(self, $0) }
        }

        @ViewBuilder
        private var payload: some View {
            if !entry.requestHeaders.isEmpty {
                collapsibleSection("Request Headers") {
                    headersView(entry.requestHeaders)
                }
            }

            if let body = entry.requestBody, let pretty = body.prettyBody {
                collapsibleSection("Request Body") {
                    codeBlock(pretty, redacted: redaction.redacting(json: body).prettyBody ?? pretty)
                }
            }

            if let headers = entry.responseHeaders, !headers.isEmpty {
                collapsibleSection("Response Headers") {
                    headersView(headers)
                }
            }

            if let body = entry.responseBody, let pretty = body.prettyBody {
                collapsibleSection("Response Body") {
                    codeBlock(pretty, redacted: redaction.redacting(json: body).prettyBody ?? pretty)
                }
            }
        }

        private func collapsibleSection(_ title: String, @ViewBuilder content: @escaping () -> some View) -> some View {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 0) {
                    content()
                }
            } label: {
                Text(title)
                    .debugDrawerFont(.heading)
            }
        }

        @ViewBuilder
        private func headersView(_ headers: [String: String]) -> some View {
            ForEach(headers.keys.sorted(), id: \.self) { key in
                let value = headers[key] ?? ""
                DebugDrawerKeyValueRow(key, value: value, redacted: redaction.masksHeader(key) ? DebugDrawerRedaction.mask : value)
            }
            // A header's value is code even when it is a word ("gzip", "close").
            .debugDrawerValueStyle(.code)
        }

        private func codeBlock(_ text: String, redacted: String) -> some View {
            DebugDrawerCodeBlock {
                RedactedText(text, redacted: redacted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
#endif
