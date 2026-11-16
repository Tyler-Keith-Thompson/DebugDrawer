#if DEBUG
    import SwiftUI

    /// Lays its subviews out left to right at their ideal sizes, starting a new line when the
    /// next would cross the trailing edge. SwiftUI has no wrapping stack; this is the smallest
    /// one the action row needs (equal spacing, lines aligned to the leading edge and to their
    /// centers).
    struct DrawerWrappingLayout: Layout {
        let spacing: CGFloat

        func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
            let lines = lines(of: subviews, width: proposal.width ?? .infinity)
            let width = lines.map(\.width).max() ?? 0
            let height = lines.map(\.height).reduce(0, +) + spacing * CGFloat(max(lines.count - 1, 0))
            return CGSize(width: width, height: height)
        }

        func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
            var top = bounds.minY
            for line in lines(of: subviews, width: bounds.width) {
                var leading = bounds.minX
                for index in line.indices {
                    let size = subviews[index].sizeThatFits(.unspecified)
                    subviews[index].place(
                        at: CGPoint(x: leading, y: top + (line.height - size.height) / 2),
                        proposal: ProposedViewSize(size)
                    )
                    leading += size.width + spacing
                }
                top += line.height + spacing
            }
        }
    }

    extension DrawerWrappingLayout {
        /// One line of subviews and the size it takes.
        fileprivate struct Line {
            var indices: [Int] = []
            var width: CGFloat = 0
            var height: CGFloat = 0
        }

        /// The subviews broken into lines no wider than `width`; a subview wider than that
        /// takes a line of its own.
        fileprivate func lines(of subviews: Subviews, width: CGFloat) -> [Line] {
            var lines: [Line] = []
            var current = Line()
            for index in subviews.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
                if needed > width, !current.indices.isEmpty {
                    lines.append(current)
                    current = Line()
                }
                current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
                current.height = max(current.height, size.height)
                current.indices.append(index)
            }
            if !current.indices.isEmpty {
                lines.append(current)
            }
            return lines
        }
    }
#endif
