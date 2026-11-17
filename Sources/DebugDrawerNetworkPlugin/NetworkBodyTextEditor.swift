#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// A body typed as text, in the code font, in a hairline box a few lines tall that grows with
    /// the text size. The mock editor's response body and the resend editor's request body use it.
    struct NetworkBodyTextEditor: View {
        @Binding var text: String
        @ScaledMetric(relativeTo: .body) private var height: CGFloat = 140
        @ScaledMetric(relativeTo: .body) private var padding: CGFloat = 4

        var body: some View {
            TextEditor(text: $text)
                .debugDrawerFont(.code)
                .autocorrectionDisabled()
                .scrollContentBackground(.hidden)
                .frame(minHeight: height)
                .padding(padding)
                .overlay {
                    RoundedRectangle(cornerRadius: 4).strokeBorder(.separator)
                }
                .accessibilityLabel("Body text")
            #if os(iOS)
                .textInputAutocapitalization(.never)
            #endif
        }
    }
#endif
