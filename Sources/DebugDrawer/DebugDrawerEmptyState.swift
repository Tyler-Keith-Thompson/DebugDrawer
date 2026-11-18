import SwiftUI

/// What a plugin shows where there is nothing to list yet: a symbol, a title and an optional
/// line saying how something gets there, centered in the panel, as Xcode's navigators show "No
/// Issues".
///
/// ```swift
/// DebugDrawerEmptyState("No requests yet", systemImage: "network") {
///     Text("Requests the app makes show here.")
/// }
/// ```
///
/// VoiceOver reads the title and the line as one element; the symbol only decorates. The type
/// exists in every build so a plugin's body compiles unchanged in release, where it draws
/// nothing.
public struct DebugDrawerEmptyState<Description: View>: View {
    let title: String
    let systemImage: String
    let description: Description

    /// An empty state with a line below the title.
    ///
    /// - Parameters:
    ///   - title: What is missing ("No files yet").
    ///   - systemImage: An SF Symbol above the title.
    ///   - description: How something gets there, in the drawer's secondary text.
    public init(_ title: String, systemImage: String, @ViewBuilder description: () -> Description) {
        self.title = title
        self.systemImage = systemImage
        self.description = description()
    }

    public var body: some View {
        #if DEBUG
            DrawerEmptyStateLayout(state: self)
        #else
            EmptyView()
        #endif
    }
}

public extension DebugDrawerEmptyState where Description == EmptyView {
    /// An empty state of a symbol and a title alone.
    ///
    /// - Parameters:
    ///   - title: What is missing.
    ///   - systemImage: An SF Symbol above the title.
    init(_ title: String, systemImage: String) {
        self.init(title, systemImage: systemImage) { EmptyView() }
    }
}

#if DEBUG
    /// The empty state's face.
    struct DrawerEmptyStateLayout<Description: View>: View {
        let state: DebugDrawerEmptyState<Description>
        @ScaledMetric(relativeTo: .body) private var padding = DrawerSpacing.rowPadding

        var body: some View {
            VStack(spacing: padding) {
                Image(systemName: state.systemImage)
                    .font(.title2)
                    .foregroundStyle(DrawerPalette.tertiaryText)
                    .accessibilityHidden(true)
                Text(state.title)
                    .debugDrawerFont(.body)
                    .foregroundStyle(DrawerPalette.secondaryText)
                state.description
                    .debugDrawerFont(.secondary)
                    .foregroundStyle(DrawerPalette.tertiaryText)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .padding(.vertical, padding * 5)
            .accessibilityElement(children: .combine)
        }
    }
#endif
