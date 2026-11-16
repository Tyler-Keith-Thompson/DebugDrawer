#if DEBUG
    import SwiftUI

    // MARK: - Explicit opt-in modifier

    public struct RenderTrackingModifier: ViewModifier {
        let label: String

        public init(_ label: String) {
            self.label = label
        }

        public func body(content: Content) -> some View {
            // An explicit return turns the view builder off, so the call can come first.
            RenderTracker.shared.recordRender(label)
            return content
        }
    }

    public extension View {
        func trackRenders(_ label: String) -> some View {
            modifier(RenderTrackingModifier(label))
        }
    }
#endif
