#if DEBUG
    import DebugDrawer
    import SwiftUI

    // A copy of the Network plugin's editor field: plugins depend on core alone, and forty lines
    // cost less than a shared module the charter rules out.

    /// An editor field: its name above its control, with an accessory beside the name, and the
    /// problem with it, if any, below.
    struct DefaultsEditorField<Content: View, Accessory: View>: View {
        let title: String
        let problem: String?
        let content: Content
        let accessory: Accessory
        @ScaledMetric(relativeTo: .body) private var padding: CGFloat = 4

        /// - Parameters:
        ///   - title: The field's name.
        ///   - problem: Why the field can't be saved, or `nil` when it can.
        ///   - content: The field's control.
        ///   - accessory: A control beside the name that changes how the field reads.
        init(_ title: String, problem: String? = nil, @ViewBuilder content: () -> Content, @ViewBuilder accessory: () -> Accessory) {
            self.title = title
            self.problem = problem
            self.content = content()
            self.accessory = accessory()
        }

        var body: some View {
            VStack(alignment: .leading, spacing: padding) {
                HStack(alignment: .center, spacing: padding) {
                    Text(title)
                        .debugDrawerFont(.label)
                        .debugDrawerForegroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Spacer(minLength: padding)
                    accessory
                }
                content
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
    }

    extension DefaultsEditorField where Accessory == EmptyView {
        /// - Parameters:
        ///   - title: The field's name.
        ///   - problem: Why the field can't be saved, or `nil` when it can.
        ///   - content: The field's control.
        init(_ title: String, problem: String? = nil, @ViewBuilder content: () -> Content) {
            self.init(title, problem: problem, content: content) { EmptyView() }
        }
    }
#endif
