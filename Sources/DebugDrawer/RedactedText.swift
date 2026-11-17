import SwiftUI

/// A value that may be sensitive: shows its redacted form, with a button that reveals the
/// value on screen until pressed again. A value with nothing redacted shows as plain text.
///
/// Revealing changes only what this view shows; copies and exports keep using the redacted
/// form.
///
/// The type exists in every build so a plugin's body compiles unchanged in release, where it
/// draws nothing.
public struct RedactedText: View {
    let value: String
    let redacted: String
    @State private var isRevealed = false
    #if DEBUG
        let inspection = Inspection<Self>() // from/for ViewInspector.
    #endif

    /// Text that shows `redacted` until the eye button beside it reveals `value`.
    ///
    /// - Parameters:
    ///   - value: The value itself.
    ///   - redacted: What to show until revealed, such as ``DebugDrawerRedaction/mask``.
    public init(_ value: String, redacted: String) {
        self.value = value
        self.redacted = redacted
    }

    public var body: some View {
        #if DEBUG
            content
                .onReceive(inspection.notice) { inspection.visit(self, $0) }
        #else
            EmptyView()
        #endif
    }

    #if DEBUG
        @ViewBuilder
        private var content: some View {
            if value == redacted {
                Text(value)
                    .debugDrawerTextSelection()
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(isRevealed ? value : redacted)
                        .debugDrawerTextSelection()
                    Button {
                        isRevealed.toggle()
                    } label: {
                        Image(systemName: isRevealed ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(isRevealed ? "Hide value" : "Reveal value")
                }
            }
        }
    #endif
}
