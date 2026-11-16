#if DEBUG
    import SwiftUI

    /// The cookie count and the buttons that reload, delete and copy the cookies.
    struct CookiesToolbar: View {
        let count: Int
        let refresh: () -> Void
        let deleteAll: () -> Void
        let copy: () -> Void
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        var body: some View {
            // At accessibility sizes the count and three buttons don't fit one row, and squeezing
            // them breaks words, so the count takes its own line and the buttons wrap below it.
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 6) {
                    countLabel
                    ViewThatFits(in: .horizontal) {
                        HStack { buttons }
                        VStack(alignment: .leading, spacing: 6) { buttons }
                    }
                }
            } else {
                HStack {
                    countLabel
                    Spacer()
                    buttons
                }
            }
        }

        private var countLabel: some View {
            Text("\(count) cookies")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
        }

        @ViewBuilder private var buttons: some View {
            Button("Refresh", action: refresh)
                .buttonStyle(.bordered)
                .controlSize(.mini)
            Button("Delete All", action: deleteAll)
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .tint(.red)
            Button("Copy", action: copy)
                .buttonStyle(.bordered)
                .controlSize(.mini)
        }
    }
#endif
