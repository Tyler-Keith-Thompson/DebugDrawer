#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// The query editor: SQL in code type, Run, and the result in the grid with Copy Result as
    /// CSV, or why it was refused or failed as an issue row.
    struct QuerySection: View {
        @Binding var sql: String
        let state: QueryState
        let onRun: () -> Void
        @ScaledMetric(relativeTo: .footnote) private var editorHeight: CGFloat = 72

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                DebugDrawerSection("Query") {
                    editor
                } footer: {
                    Text("Runs one statement that reads: a SELECT, or a pragma that describes a table. " +
                        "It reads up to \(SQLiteStore.queryRowLimit) rows.")
                }
                DebugDrawerActionRow {
                    Button("Run", action: onRun)
                        .debugDrawerButtonStyle(.primary)
                        .disabled(state == .running || sql.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityHint("Runs the query read-only")
                    if case let .finished(result) = state {
                        DebugDrawerCopyButton("Copy Result as CSV") { result.csv }
                    }
                }
                result
            }
        }

        @ViewBuilder private var editor: some View {
            #if os(tvOS) || os(watchOS)
                // No TextEditor here: the field edits in the system's full-screen keyboard.
                TextField("SELECT * FROM …", text: $sql, axis: .vertical)
                    .debugDrawerFont(.code)
                    .accessibilityLabel("SQL query")
            #else
                TextEditor(text: $sql)
                    .debugDrawerFont(.code)
                    .autocorrectionDisabled()
                    .scrollContentBackground(.hidden)
                    .frame(height: editorHeight)
                    .padding(4)
                    .overlay(alignment: .topLeading) {
                        if sql.isEmpty {
                            Text("SELECT * FROM …")
                                .debugDrawerFont(.code)
                                .debugDrawerForegroundStyle(.tertiary)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                    }
                    .background(.background, in: RoundedRectangle(cornerRadius: 6))
                    .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(.separator) }
                    .accessibilityLabel("SQL query")
                #if os(iOS) || os(visionOS)
                    .textInputAutocapitalization(.never)
                #endif
            #endif
        }

        @ViewBuilder private var result: some View {
            switch state {
            case .idle:
                EmptyView()
            case .running:
                Text("Running…")
                    .debugDrawerFont(.secondary)
                    .debugDrawerForegroundStyle(.secondary)
                    .debugDrawerRowPadding()
            case let .finished(result):
                ResultGrid(result: result)
            case let .failed(error):
                DebugDrawerIssueRow(error.title, severity: .error) {
                    Text(error.explanation)
                }
            }
        }
    }
#endif
