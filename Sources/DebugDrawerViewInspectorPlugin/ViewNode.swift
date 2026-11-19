#if DEBUG
    import Foundation

    // MARK: - View hierarchy model

    // Values read from the app's views, with no reference to one: a snapshot can be kept, compared
    // and encoded while the views it was read from change or go. `_ViewHierarchyReader` reads it
    // from AppKit or UIKit.

    /// One view of the key window's hierarchy, as it was when the snapshot was taken, with its
    /// subviews.
    struct ViewNode: Identifiable, Codable, Equatable, Sendable {
        var id = UUID()
        /// The view's class, unqualified.
        let className: String
        /// The view's frame in its superview's coordinates.
        let frame: CGRect
        let accessibilityLabel: String?
        /// The view's accessibility role; UIKit has traits rather than roles, so `nil` on iOS.
        let accessibilityRole: String?
        let isHidden: Bool
        let alpha: CGFloat
        /// Whether the view's layer masks to its bounds.
        let hasClipping: Bool
        let cornerRadius: CGFloat
        /// The layer's background color as `#RRGGBB`, or `nil` with none.
        let backgroundColor: String?
        let constraintCount: Int
        let subviewCount: Int
        /// The subviews, as deep as the snapshot read.
        let children: [ViewNode]
    }
#endif
