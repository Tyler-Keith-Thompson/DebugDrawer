#if DEBUG
    import SwiftUI

    /// Hands its content a drawer's redaction rules, and draws it again as they change, as
    /// `GeometryReader` hands its content the space it has.
    ///
    /// For a plugin's view that masks what it shows and copies by the rules of the drawer it is
    /// shown in (`@Environment(\.showingDrawer)`), which `@Environment` alone doesn't watch.
    package struct DebugDrawerRedactionReader<Content: View>: View {
        @ObservedObject private var drawer: DebugDrawer
        private let content: (DebugDrawerRedaction) -> Content

        /// - Parameters:
        ///   - drawer: The drawer whose rules to follow; `nil`, outside any drawer (a view drawn
        ///     alone), follows `DebugDrawer.shared`'s, which the app sets.
        ///   - content: The view for the rules.
        package init(_ drawer: DebugDrawer?, @ViewBuilder content: @escaping (DebugDrawerRedaction) -> Content) {
            self.drawer = drawer ?? .shared
            self.content = content
        }

        package var body: some View {
            content(drawer.redaction)
        }
    }
#endif
