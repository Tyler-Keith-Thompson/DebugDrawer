#if DEBUG && (os(macOS) || os(iOS))
    import CoreGraphics
    import DebugDrawer
    #if os(macOS)
        import AppKit
    #else
        import UIKit
    #endif

    /// Where one of the app's views is, as a value: its frame in an overlay's coordinates, how
    /// deep it sits in its window and what is drawn over it, read without keeping or changing the
    /// view.
    struct ViewOutline: Equatable {
        /// The view's bounds in the overlay's content, in points from its top-leading corner.
        var frame: CGRect
        /// How many superviews the view has below the root that was read.
        var depth: Int
        /// The rectangles, in the overlay's content, of what the app draws over the view (a sheet
        /// presented over it, a window above it), inside which its outline isn't drawn.
        var covers: [CGRect] = []

        /// The parts of the outline that are drawn: each side of `frame` inset by half a line, so
        /// the line lies inside the view as a layer's border does, less where a cover lies over it.
        ///
        /// - Complexity: O(*c*²), where *c* is the number of covers.
        var visibleEdges: [OutlineEdge] {
            let rect = frame.insetBy(dx: 0.5, dy: 0.5)
            // A view less than a point across has no room inside it for the line.
            guard !rect.isNull else { return [] }
            let horizontal = [rect.minY, rect.maxY].flatMap { row in
                let hidden = covers.filter { $0.minY <= row && row <= $0.maxY }.map { $0.minX ... $0.maxX }
                return Self.visibleSpans(of: rect.minX ..< rect.maxX, hiddenBy: hidden)
                    .map { OutlineEdge(start: CGPoint(x: $0.lowerBound, y: row), end: CGPoint(x: $0.upperBound, y: row)) }
            }
            let vertical = [rect.minX, rect.maxX].flatMap { column in
                let hidden = covers.filter { $0.minX <= column && column <= $0.maxX }.map { $0.minY ... $0.maxY }
                return Self.visibleSpans(of: rect.minY ..< rect.maxY, hiddenBy: hidden)
                    .map { OutlineEdge(start: CGPoint(x: column, y: $0.lowerBound), end: CGPoint(x: column, y: $0.upperBound)) }
            }
            return horizontal + vertical
        }

        /// This outline with those of `rects` that overlap it as its covers, or `nil` when they
        /// leave nothing of it to draw.
        func covered(by rects: [CGRect]) -> ViewOutline? {
            var outline = self
            outline.covers = rects.filter { $0.intersects(frame) }
            return outline.covers.isEmpty || !outline.visibleEdges.isEmpty ? outline : nil
        }

        /// The parts of `span` that no range in `hidden` overlaps, in order, none empty.
        private static func visibleSpans(of span: Range<CGFloat>, hiddenBy hidden: [ClosedRange<CGFloat>]) -> [Range<CGFloat>] {
            hidden.reduce([span]) { spans, hidden in
                spans.flatMap { span in
                    guard hidden.overlaps(span) else { return [span] }
                    return [span.lowerBound ..< max(span.lowerBound, hidden.lowerBound), min(hidden.upperBound, span.upperBound) ..< span.upperBound]
                        .filter { !$0.isEmpty }
                }
            }
        }

        #if os(macOS)
            /// The outlines of `root` and every view under it that is shown and has an area, root
            /// first, each placed by `place` from the view's bounds in its window's coordinates;
            /// an outline is left out inside the window's opaque child windows, and left out
            /// entirely when nothing of it shows.
            ///
            /// A sheet is ordered above the window and its children, overlay included, so it hides
            /// the outlines as it hides the views. A child window isn't: children stack in the
            /// order they were added, so one added before the overlay sits under it, and its
            /// frame is cut out of the outlines instead. The drawer's own windows and see-through
            /// children cut nothing.
            ///
            /// - Parameters:
            ///   - root: A window's content view.
            ///   - place: Converts a rectangle in the window's base coordinates to the overlay's.
            /// - Returns: The outlines, depth first.
            @MainActor
            static func read(from root: NSView, placing place: (CGRect) -> CGRect) -> [ViewOutline] {
                var outlines: [ViewOutline] = []
                root.appendOutlines(depth: 0, to: &outlines, placing: place)
                guard let window = root.window else { return outlines }
                let covers = (window.childWindows ?? []).filter { $0.isVisible && $0.hidesWhatIsUnder && !isDebugDrawerWindow($0) }
                    .map { place(window.convertFromScreen($0.frame)) }
                return covers.isEmpty ? outlines : outlines.compactMap { $0.covered(by: covers) }
            }
        #else
            /// The outlines of each of `windows` and every view under it that is shown and has an
            /// area, each window first, in `overlay`'s coordinates; an outline is left out where
            /// something drawn after its view covers it, and left out entirely when nothing of it
            /// shows.
            ///
            /// What covers a view: a view controller's view presented over it (a sheet, a form
            /// sheet, a popover, an alert, each one of a stack of sheets over those under it) and
            /// a later window whose root view has an opaque background. A presentation over the
            /// full screen or the current context, or a custom one, covers only when its view's
            /// background is opaque, since those are often see-through.
            ///
            /// - Parameters:
            ///   - windows: The app's windows, back to front.
            ///   - overlay: The window whose coordinates the outlines are in.
            /// - Returns: The outlines, back to front, each window's depth first.
            @MainActor
            static func read(from windows: [UIWindow], in overlay: UIWindow) -> [ViewOutline] {
                var collector = OutlineCollector()
                for window in windows {
                    let place = { (rect: CGRect) in window.convert(rect, to: overlay) }
                    if let root = window.rootViewController?.viewIfLoaded, root.window === window, !root.isHidden, root.hasOpaqueBackground {
                        collector.cover(place(root.convert(root.bounds, to: nil)))
                    }
                    // The caller picked the window, so it is outlined whether or not it is hidden
                    // (one made in code is until it is shown); its views are outlined while they
                    // show.
                    if !window.bounds.isEmpty { collector.append(ViewOutline(frame: place(window.bounds), depth: 0)) }
                    let covering = window.presentedViews
                    for subview in window.subviews {
                        subview.appendOutlines(depth: 1, to: &collector, covering: covering, placing: place)
                    }
                }
                return collector.outlines
            }
        #endif
    }

    /// A straight part of an outline, in the overlay's content.
    struct OutlineEdge: Equatable {
        var start: CGPoint
        var end: CGPoint
    }

    #if os(macOS)
        extension NSWindow {
            /// Whether the window hides what is under it: shown fully and with a background no
            /// window under it shows through.
            @MainActor
            fileprivate var hidesWhatIsUnder: Bool {
                alphaValue >= 1 && (backgroundColor.usingColorSpace(.sRGB)?.alphaComponent ?? 0) >= 1
            }
        }

        extension NSView {
            // The grid's probe is the plugin's, so it is no view of the app's to outline.
            @MainActor
            fileprivate func appendOutlines(depth: Int, to outlines: inout [ViewOutline], placing place: (CGRect) -> CGRect) {
                guard !isHidden, alphaValue > 0, !(self is GridProbeView) else { return }
                if bounds.width > 0, bounds.height > 0 {
                    outlines.append(ViewOutline(frame: place(convert(bounds, to: nil)), depth: depth))
                }
                for subview in subviews {
                    subview.appendOutlines(depth: depth + 1, to: &outlines, placing: place)
                }
            }
        }
    #else
        /// Outlines in the order their views are drawn, back to front, and the covers met along the
        /// way: a cover hides the outlines collected before it, never those after (its own view's
        /// and its subviews').
        private struct OutlineCollector {
            private var collected: [ViewOutline] = []
            private var covers: [(rect: CGRect, from: Int)] = []

            mutating func append(_ outline: ViewOutline) {
                collected.append(outline)
            }

            mutating func cover(_ rect: CGRect) {
                guard !rect.isEmpty else { return }
                covers.append((rect, collected.count))
            }

            /// Each outline with the covers over it, without those nothing of which shows.
            var outlines: [ViewOutline] {
                collected.enumerated().compactMap { index, outline in
                    outline.covered(by: covers.filter { $0.from > index }.map(\.rect))
                }
            }
        }

        extension UIWindow {
            /// The views of every view controller presented in this window that hide what is
            /// under them.
            @MainActor
            fileprivate var presentedViews: Set<ObjectIdentifier> {
                // Walks the children too: a presentation in a context of its own
                // (definesPresentationContext) hangs off the child that defines it.
                var visited = Set<ObjectIdentifier>()
                var views = Set<ObjectIdentifier>()
                var pending = rootViewController.map { [$0] } ?? []
                while let controller = pending.popLast() {
                    guard visited.insert(ObjectIdentifier(controller)).inserted else { continue }
                    pending += controller.children
                    guard let presented = controller.presentedViewController else { continue }
                    pending.append(presented)
                    if presented.hidesWhatIsUnder, let view = presented.presentationController?.presentedView ?? presented.viewIfLoaded {
                        views.insert(ObjectIdentifier(view.outermost(in: presented.presentationController?.containerView)))
                    }
                }
                return views
            }
        }

        extension UIViewController {
            /// Whether this presented view controller's view hides what it is presented over.
            @MainActor
            fileprivate var hidesWhatIsUnder: Bool {
                switch modalPresentationStyle {
                case .overFullScreen, .overCurrentContext, .custom, .none:
                    viewIfLoaded?.hasOpaqueBackground ?? false
                default:
                    true
                }
            }
        }

        extension UIView {
            /// The view in `container` that holds this one: what a presentation draws there, a
            /// sheet's card with its corners and shadow around the presented view; this view when
            /// it isn't in `container`.
            @MainActor
            fileprivate func outermost(in container: UIView?) -> UIView {
                guard let container, self !== container, isDescendant(of: container) else { return self }
                var view = self
                while let superview = view.superview, superview !== container {
                    view = superview
                }
                return view
            }

            @MainActor
            fileprivate var hasOpaqueBackground: Bool {
                (backgroundColor?.cgColor.alpha ?? 0) >= 1
            }

            // The grid's probe is the plugin's, so it is no view of the app's to outline.
            @MainActor
            fileprivate func appendOutlines(
                depth: Int, to collector: inout OutlineCollector, covering: Set<ObjectIdentifier>, placing place: (CGRect) -> CGRect
            ) {
                guard !isHidden, alpha > 0, !(self is GridProbeView) else { return }
                let frame = place(convert(bounds, to: nil))
                if covering.contains(ObjectIdentifier(self)) { collector.cover(frame) }
                if bounds.width > 0, bounds.height > 0 {
                    collector.append(ViewOutline(frame: frame, depth: depth))
                }
                for subview in subviews {
                    subview.appendOutlines(depth: depth + 1, to: &collector, covering: covering, placing: place)
                }
            }
        }
    #endif
#endif
