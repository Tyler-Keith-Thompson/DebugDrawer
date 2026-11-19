#if DEBUG && os(iOS)
    import SwiftUI
    import UIKit

    // The scroll view's half of the text view's delegate: whether the lines follow.
    extension ConsoleTextView.Coordinator {
        // Only the person's scrolls change whether the lines follow; UIKit's own (a new
        // frame, a relayout, a new content size) never do.
        func scrollViewWillBeginDragging(_: UIScrollView) {
            textView?.isScrolledByPerson = true
        }

        func scrollViewDidEndDragging(_: UIScrollView, willDecelerate decelerate: Bool) {
            if !decelerate { endUserScroll() }
        }

        func scrollViewDidEndDecelerating(_: UIScrollView) {
            endUserScroll()
        }

        /// A scroll that ends within reach of the end settles on it.
        private func endUserScroll() {
            textView?.isScrolledByPerson = false
            textView?.pinEnd()
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard textView?.isScrolledByPerson == true else { return }
            let contentHeight = scrollView.contentSize.height
            let scrollOffset = scrollView.contentOffset.y + scrollView.bounds.height
            let atBottom = contentHeight - scrollOffset < 20
            // Set on the view at once, so a layout after the scroll ends but before
            // SwiftUI's next update doesn't pull the lines back to the end.
            textView?.followsEnd = atBottom
            if isFollowing.wrappedValue != atBottom {
                isFollowing.wrappedValue = atBottom
            }
        }

        /// A tap on the status bar scrolls to the first line: the person's scroll too.
        func scrollViewShouldScrollToTop(_: UIScrollView) -> Bool {
            textView?.isScrolledByPerson = true
            return true
        }

        func scrollViewDidScrollToTop(_: UIScrollView) {
            endUserScroll()
        }
    }
#endif
