#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// A cookie's name, then its domain over the store it is in, with a button to delete it;
    /// tapping the name shows the rest. At accessibility text sizes the domain and store move
    /// under the name, so neither is squeezed to a few letters.
    struct CookieRow: View {
        let stored: StoredCookie
        let redaction: DebugDrawerRedaction
        let isExpanded: Bool
        let toggle: () -> Void
        let onDelete: () -> Void

        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        var body: some View {
            VStack(alignment: .leading, spacing: 2) {
                if dynamicTypeSize.isAccessibilitySize {
                    HStack(alignment: .firstTextBaseline) {
                        expandButton
                        Spacer()
                        deleteButton
                    }
                    location(alignment: .leading)
                } else {
                    HStack {
                        expandButton
                        Spacer()
                        location(alignment: .trailing)
                        deleteButton
                    }
                }

                if isExpanded {
                    CookieDetails(stored: stored, redaction: redaction)
                        .padding(.leading, 16)
                }
            }
        }

        private var expandButton: some View {
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.15)) { toggle() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .debugDrawerFont(.secondary)
                        .debugDrawerForegroundStyle(.secondary)
                        .accessibilityHidden(true)
                    // One line cut in the middle, as the UserDefaults keys are, until expanded;
                    // VoiceOver reads it whole.
                    Text(stored.name)
                        .debugDrawerFont(.code)
                        .fontWeight(.medium)
                        .debugDrawerForegroundStyle(.primary)
                        .lineLimit(isExpanded ? nil : 1)
                        .truncationMode(.middle)
                        .help(stored.name)
                }
            }
            .debugDrawerButtonStyle(.plain)
            .accessibilityLabel(stored.name)
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
        }

        private func location(alignment: HorizontalAlignment) -> some View {
            VStack(alignment: alignment, spacing: 0) {
                // Cut in the middle like the name, and whole once the cookie is expanded.
                Text(stored.domain)
                    .debugDrawerFont(.code)
                    .debugDrawerForegroundStyle(.tertiary)
                    .lineLimit(isExpanded ? nil : 1)
                    .truncationMode(.middle)
                    .help(stored.domain)
                Text(stored.store.title)
                    .debugDrawerFont(.secondary)
                    .debugDrawerForegroundStyle(.tertiary)
                    .accessibilityLabel("in \(stored.store.title)")
            }
            .accessibilityElement(children: .combine)
        }

        private var deleteButton: some View {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
            }
            .debugDrawerButtonStyle(.borderless)
            .accessibilityLabel("Delete \(stored.name) from \(stored.store.title)")
        }
    }
#endif
