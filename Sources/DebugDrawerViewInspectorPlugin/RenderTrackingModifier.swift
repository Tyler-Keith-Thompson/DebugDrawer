import SwiftUI

// MARK: - Explicit opt-in modifier

// The modifier compiles in every configuration; release builds record nothing and return the
// content unchanged.

public struct RenderTrackingModifier: ViewModifier {
    let label: String

    public init(_ label: String) {
        self.label = label
    }

    public func body(content: Content) -> some View {
        #if DEBUG
            // An explicit return turns the view builder off, so the call can come first.
            RenderTracker.shared.recordRender(label)
        #endif
        return content
    }
}

public extension View {
    func trackRenders(_ label: String) -> some View {
        #if DEBUG
            modifier(RenderTrackingModifier(label))
        #else
            self
        #endif
    }
}
