import SwiftUI

/// A small bordered button that copies text to the clipboard.
///
/// The text is read when the button is pressed, so a report is built only when someone copies
/// it. Pass what a copy may carry: mask sensitive values with the drawer's
/// ``DebugDrawerRedaction`` first.
///
/// The type exists in every build so a plugin's body compiles unchanged in release, where it
/// draws nothing.
public struct DebugDrawerCopyButton: View {
    let title: String
    let value: @MainActor () -> String?

    /// - Parameters:
    ///   - title: The button's title, which names what it copies ("Copy Value").
    ///   - value: The text to copy, read on each press; `nil` copies nothing and leaves the
    ///     clipboard as it was.
    public init(_ title: String, value: @escaping @MainActor () -> String?) {
        self.title = title
        self.value = value
    }

    public var body: some View {
        #if DEBUG
            content
        #else
            EmptyView()
        #endif
    }
}

#if DEBUG
    extension DebugDrawerCopyButton {
        private var content: some View {
            Button(title) {
                if let text = value() {
                    debugDrawerCopyToClipboard(text)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityHint("Copies to the clipboard")
        }
    }
#endif
