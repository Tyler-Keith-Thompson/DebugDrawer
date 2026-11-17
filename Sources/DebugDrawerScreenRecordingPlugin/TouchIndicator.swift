#if DEBUG
    import CoreGraphics

    /// The circle a recording shows where a finger touches: drawn into the frames only, never on
    /// screen.
    enum TouchIndicator {
        /// The circle's radius, in points: about a fingertip.
        static let radius: CGFloat = 22

        /// Draws a circle centred on each of `points` (in the context's current coordinates): a
        /// translucent white fill with a dark ring, which shows on light and dark content alike.
        static func draw(at points: [CGPoint], in context: CGContext) {
            guard !points.isEmpty else { return }
            context.saveGState()
            defer { context.restoreGState() }
            for point in points {
                let circle = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
                context.setFillColor(CGColor(gray: 1, alpha: 0.55))
                context.fillEllipse(in: circle)
                context.setStrokeColor(CGColor(gray: 0, alpha: 0.45))
                context.setLineWidth(2)
                context.strokeEllipse(in: circle.insetBy(dx: 1, dy: 1))
            }
        }
    }
#endif
