import SwiftUI

// The one SwiftUI piece of the module, in it rather than a module of its own or the host's: it
// draws nothing and only reads the review, and without it a string a body read before the mode
// changed would keep its old text until something else redrew it. A new identity rather than an
// environment value, as `debugLocalization()` does: a body that read a string through the review
// reads no environment value a change could invalidate, so only rebuilding it reads the string
// again.

public extension View {
    /// Draws the view again whenever `review`'s mode changes, so the strings its body reads through
    /// the review show the new mode, the keys or pseudo-localized text a sidecar asked for, or
    /// their translations again as the session ends.
    ///
    /// The view gets a new identity on each change, so the `@State` inside it, its scroll
    /// positions and navigation start over. Apply it to the app's root view:
    ///
    /// ```swift
    /// ContentView()
    ///     .localizationReview()
    /// ```
    ///
    /// - Parameter review: The review the view's strings are read through;
    ///   ``LocalizationReview/shared`` unless given.
    /// - Returns: The view, redrawn as the mode changes.
    func localizationReview(_ review: LocalizationReview = .shared) -> some View {
        modifier(LocalizationReviewRedraw(review: review))
    }
}

/// Gives the content the review's mode as its identity.
private struct LocalizationReviewRedraw: ViewModifier {
    @ObservedObject var review: LocalizationReview

    func body(content: Content) -> some View {
        content.id(review.snapshot.mode)
    }
}
