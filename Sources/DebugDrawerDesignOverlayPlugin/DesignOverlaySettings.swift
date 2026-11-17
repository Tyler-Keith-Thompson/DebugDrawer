#if DEBUG
    import CoreGraphics

    /// How the mockup is drawn: whether it shows, its opacity, its offset, its scale and its blend.
    /// Saved beside the mockup, so a relaunch draws it the same way.
    struct DesignOverlaySettings: Codable, Equatable, Sendable {
        /// The opacities the slider offers, from almost clear to opaque.
        static let opacityRange: ClosedRange<Double> = 0.05 ... 1
        /// How far the steppers move the mockup, in points either way.
        static let offsetRange: ClosedRange<CGFloat> = -10000 ... 10000

        /// Whether the mockup is drawn.
        var isVisible = true
        /// The mockup's opacity, within ``opacityRange``.
        var opacity = 0.5
        /// How far the mockup is from the window's top-leading corner, in points.
        var offset = CGSize.zero
        var scale = MockupScale.automatic
        var blend = MockupBlend.normal

        /// These settings with the mockup moved by `translation`, rounded to whole points so the
        /// steppers move it from there, and kept within ``offsetRange``.
        func moved(by translation: CGSize) -> Self {
            var moved = self
            moved.offset = CGSize(
                width: Self.offsetRange.clamping((offset.width + translation.width).rounded()),
                height: Self.offsetRange.clamping((offset.height + translation.height).rounded())
            )
            return moved
        }

        /// The opacity as a whole percentage ("50%").
        var opacityText: String {
            "\(Int((opacity * 100).rounded()))%"
        }
    }

    extension ClosedRange where Bound: Comparable {
        /// `value`, or the nearer bound when it lies outside.
        fileprivate func clamping(_ value: Bound) -> Bound {
            Swift.min(Swift.max(value, lowerBound), upperBound)
        }
    }
#endif
