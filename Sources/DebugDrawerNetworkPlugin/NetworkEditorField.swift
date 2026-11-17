#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// An editor field: its name above its control, and the problem with it, if any, below. The
    /// mock and condition editors lay out every field with it.
    struct NetworkEditorField<Content: View>: View {
        let title: String
        let problem: String?
        let content: Content
        @ScaledMetric(relativeTo: .body) private var padding: CGFloat = 4

        /// - Parameters:
        ///   - title: The field's name.
        ///   - problem: Why the field can't be saved, or `nil` when it can.
        ///   - content: The field's control.
        init(_ title: String, problem: String? = nil, @ViewBuilder content: () -> Content) {
            self.title = title
            self.problem = problem
            self.content = content()
        }

        var body: some View {
            VStack(alignment: .leading, spacing: padding) {
                Text(title)
                    .debugDrawerFont(.label)
                    .debugDrawerForegroundStyle(.secondary)
                    .accessibilityHidden(true)
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

    /// A choice of a few words: segments, or at accessibility text sizes, where the segments would
    /// shrink their words past reading, a menu.
    struct NetworkEditorChoice<Choice>: View
        where Choice: CaseIterable & Identifiable & Hashable, Choice.AllCases: RandomAccessCollection {
        let title: String
        @Binding var selection: Choice
        /// The words a choice is shown as.
        let label: (Choice) -> String
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        /// - Parameters:
        ///   - title: What is chosen, which labels the control for VoiceOver.
        ///   - selection: The choice.
        ///   - label: The words a choice is shown as.
        init(_ title: String, selection: Binding<Choice>, label: @escaping (Choice) -> String) {
            self.title = title
            _selection = selection
            self.label = label
        }

        var body: some View {
            let picker = Picker(title, selection: $selection) {
                ForEach(Choice.allCases) { Text(label($0)).tag($0) }
            }
            .labelsHidden()
            .accessibilityLabel(title)
            if dynamicTypeSize.isAccessibilitySize {
                picker
                    .pickerStyle(.menu)
                    .fixedSize()
            } else {
                picker
                    .pickerStyle(.segmented)
                    .accessibilityElement(children: .contain)
            }
        }
    }

    extension NetworkEditorChoice where Choice: RawRepresentable, Choice.RawValue == String {
        /// A choice shown by its raw values.
        init(_ title: String, selection: Binding<Choice>) {
            self.init(title, selection: selection) { $0.rawValue }
        }
    }
#endif
