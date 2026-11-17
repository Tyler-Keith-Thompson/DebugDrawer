#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// The search field, with the `.*` toggle beside it that reads the text as a regular
    /// expression and an accessory after that, and, while the text isn't one, why, under the
    /// field.
    struct ConsoleSearchField<Accessory: View>: View {
        @Binding var text: String
        @Binding var isRegularExpression: Bool
        /// Why the text isn't a pattern; `nil` while it is one, or isn't read as one.
        let issue: ConsoleSearch.InvalidPattern?
        /// What follows the toggle, such as a menu.
        @ViewBuilder var accessory: Accessory

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    TextField(isRegularExpression ? "Regular expression" : "Search logs...", text: $text)
                        .debugDrawerTextFieldStyle()
                        .accessibilityLabel(isRegularExpression ? "Search logs by regular expression" : "Search logs")
                    Button {
                        isRegularExpression.toggle()
                    } label: {
                        Text(".*")
                            .debugDrawerFont(.code)
                    }
                    // Filled while on, like Xcode's find options.
                    .debugDrawerButtonStyle(isRegularExpression ? .primary : .secondary)
                    .fixedSize()
                    .accessibilityLabel("Regular expression")
                    .accessibilityValue(isRegularExpression ? "On" : "Off")
                    .accessibilityAddTraits(isRegularExpression ? .isSelected : [])
                    .help("Search by regular expression")
                    accessory
                }
                if let issue {
                    DebugDrawerIssueRow("Invalid pattern", severity: .error) {
                        Text(issue.message)
                    }
                }
            }
        }
    }

    extension ConsoleSearchField where Accessory == EmptyView {
        /// The field and its toggle, with nothing after them.
        init(text: Binding<String>, isRegularExpression: Binding<Bool>, issue: ConsoleSearch.InvalidPattern?) {
            self.init(text: text, isRegularExpression: isRegularExpression, issue: issue) { EmptyView() }
        }
    }
#endif
