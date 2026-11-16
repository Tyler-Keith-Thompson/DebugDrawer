import SwiftUI

/// A path, identifier or other long token, in the drawer's monospaced code type: one line, cut
/// in the middle so both its start and its end show. Tapping or clicking it shows the whole value,
/// wrapped, and again returns it to one line. The text is selectable, and on the Mac its tooltip
/// is the whole value.
///
/// ```swift
/// DebugDrawerCodeText(library.path)
///     .foregroundStyle(.secondary)
/// ```
///
/// The type exists in every build so a plugin's body compiles unchanged in release, where it
/// draws nothing.
public struct DebugDrawerCodeText: View {
    let text: String
    @State private var isExpanded = false
    #if DEBUG
        let inspection = Inspection<Self>() // from/for ViewInspector.
    #endif

    /// - Parameter text: The value, shown in full when expanded.
    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        #if DEBUG
            content
                .onReceive(inspection.notice) { inspection.visit(self, $0) }
        #else
            EmptyView()
        #endif
    }
}

#if DEBUG
    extension DebugDrawerCodeText {
        private var content: some View {
            Text(text)
                .debugDrawerFont(.code)
                .lineLimit(isExpanded ? nil : 1)
                .truncationMode(.middle)
                .fixedSize(horizontal: false, vertical: isExpanded)
                .frame(maxWidth: .infinity, alignment: .leading)
                .debugDrawerTextSelection()
                .contentShape(Rectangle())
                .onTapGesture { isExpanded.toggle() }
                .help(text)
                .accessibilityAddTraits(.isButton)
                .accessibilityHint(isExpanded ? "Shows it on one line" : "Shows the whole value")
        }
    }
#endif
