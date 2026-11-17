#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// The Ignored hosts section: each ignored host or domain with Remove, then a field to type
    /// one and Ignore Host. Typed text that isn't a host says why under the field and adds nothing.
    /// A problem reading or saving the list shows above it.
    ///
    /// It keeps the typed text and its problem.
    struct NetworkIgnoreListSection: View {
        let domains: [NetworkIgnoredDomain]
        let issue: NetworkMocksIssue?
        let add: (NetworkIgnoredDomain) -> Void
        let remove: (NetworkIgnoredDomain) -> Void
        @State var text = ""
        @State var problem: NetworkIgnoredDomain.ParseError?
        let inspection = Inspection<Self>()

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                DebugDrawerSection("Ignored hosts") {
                    if let issue {
                        DebugDrawerIssueRow(issue == .notSaved ? "Not saved" : "Not loaded", severity: issue == .notSaved ? .warning : .error) {
                            Text(issue.message(about: "ignored hosts"))
                        }
                    }
                    ForEach(domains, id: \.self) { domain in
                        DebugDrawerRow(domain.name) {
                            Button("Remove", role: .destructive) { remove(domain) }
                                .debugDrawerButtonStyle(.destructive)
                                .accessibilityLabel("Remove \(domain.name)")
                        }
                    }
                } footer: {
                    Text(domains.isEmpty
                        ? "No ignored hosts. Ignore one from a request's detail, or type one below, to hide its requests "
                        + "and its subdomains' from the log."
                        : "Requests to these hosts and their subdomains are hidden from the log. "
                        + "They are still captured and in bug reports; the note under the log shows them.")
                }
                NetworkEditorField("Host or domain", problem: problem?.message) {
                    TextField("analytics.example.com", text: $text)
                        .debugDrawerTextFieldStyle()
                        .autocorrectionDisabled()
                    #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    #endif
                        .onSubmit(addTyped)
                        .onChange(of: text) { problem = nil }
                        .accessibilityLabel("Host or domain to ignore")
                }
                DebugDrawerActionRow {
                    Button("Ignore Host", action: addTyped)
                        .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityLabel("Ignore Host")
                        .accessibilityHint("Hides the requests to the host typed, and its subdomains, from the log")
                }
            }
            .onReceive(inspection.notice) { inspection.visit(self, $0) }
        }

        /// Ignores the typed host and empties the field, or says why it isn't one.
        private func addTyped() {
            do {
                let domain = try NetworkIgnoredDomain(parsing: text)
                add(domain)
                text = ""
                problem = nil
            } catch {
                problem = error
            }
        }
    }
#endif
