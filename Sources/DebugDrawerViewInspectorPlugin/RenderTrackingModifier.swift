import SwiftUI

public extension View {
    /// Counts each evaluation of the body this is applied in, under `name`, for the View Inspector
    /// plugin's SwiftUI Renders list.
    ///
    /// Apply it to the outermost view of the body to count, so it is created each time that body
    /// is: `.trackRenders(_:)` applied to a child from its parent's body counts the parent's
    /// evaluations instead. With Flash Renders on in the plugin, the view's frame flashes on each
    /// evaluation, unless Reduce Motion is on. Release builds return the view unchanged.
    ///
    /// - Parameter name: The name the counts are listed under; views given the same name share a
    ///   count.
    /// - Returns: The view, counted.
    func trackRenders(_ name: String) -> some View {
        #if DEBUG
            modifier(RenderTrackingModifier(name: name, evaluation: RenderEvaluation()))
        #else
            self
        #endif
    }
}

#if DEBUG
    /// Records an evaluation each time its body runs, and flashes the view's frame through an
    /// overlay that leaves the view's own layout alone.
    struct RenderTrackingModifier: ViewModifier {
        let name: String
        /// New for each evaluation of the body that applied the modifier, so SwiftUI never finds
        /// two modifiers equal and skips this body: it runs once per evaluation of that body.
        let evaluation: RenderEvaluation

        func body(content: Content) -> some View {
            let count = RenderTracker.shared.record(name)
            return content.overlay { RenderFlash(trigger: count) }
        }
    }

    /// A value that differs each time one is made.
    struct RenderEvaluation: Equatable {
        private let id = UUID()
    }
#endif
