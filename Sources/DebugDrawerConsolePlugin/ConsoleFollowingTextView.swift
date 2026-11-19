#if DEBUG && os(iOS)
    import UIKit

    /// The console's text view on iOS, which keeps its last line at the bottom while it follows.
    ///
    /// UIKit moves the content itself, outside any scroll the view asks for: a new frame (the
    /// well's height scales with Dynamic Type), a relayout, or TextKit refining its estimated
    /// content height as it lays out the lines it shows. Each of those ends in `layoutSubviews` or
    /// a new `contentSize`, so the view pins its end again there, rather than once when the text
    /// changes, before it has the frame it is drawn at.
    ///
    /// While the person scrolls it, the view leaves the offset to them.
    final class ConsoleFollowingTextView: UITextView {
        /// Whether the person is scrolling the view: from the start of a drag to where it, or the
        /// deceleration after it, ends. Set by the scroll view's delegate, which is told both.
        var isScrolledByPerson = false

        /// Whether the end of the text stays in view; setting it to `true` scrolls there.
        var followsEnd = true {
            didSet {
                if followsEnd, !oldValue { pinEnd() }
            }
        }

        override var contentSize: CGSize {
            didSet {
                if contentSize != oldValue { pinEnd() }
            }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            pinEnd()
        }

        /// Scrolls to the end while the view follows it and nobody is scrolling it.
        func pinEnd() {
            guard followsEnd, !isScrolledByPerson else { return }
            scrollToEnd()
        }

        /// Shows the end of the text, without animation; does nothing where it already shows.
        private func scrollToEnd() {
            let insets = adjustedContentInset
            let end = CGPoint(
                x: contentOffset.x,
                y: max(-insets.top, contentSize.height + insets.bottom - bounds.height)
            )
            if contentOffset != end {
                setContentOffset(end, animated: false)
            }
        }
    }
#endif
