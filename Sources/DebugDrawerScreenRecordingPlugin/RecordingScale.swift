#if DEBUG
    import CoreGraphics

    /// How many pixels a point of the recorded window takes in the movie.
    enum RecordingScale {
        /// The longest side a movie is recorded at: drawing and encoding a larger frame 30 times a
        /// second costs more than it adds to a bug report.
        static let maximumDimension: CGFloat = 1920

        /// The screen's own scale, or less when that would make the longest side of `size` (in
        /// points) longer than ``maximumDimension`` pixels; 1 for an empty size.
        static func scale(for size: CGSize, screenScale: CGFloat) -> CGFloat {
            let longest = max(size.width, size.height)
            guard longest > 0, screenScale > 0 else { return 1 }
            return min(screenScale, maximumDimension / longest)
        }
    }
#endif
