#if DEBUG
    import CoreGraphics

    /// How large the mockup is drawn: as wide as the window, or its pixels at a screen scale.
    ///
    /// Mockups are usually exported at @2x or @3x, so a mockup's pixel is a third or a half of a
    /// point; ``automatic`` infers which from the mockup's width against the window's.
    enum MockupScale: String, Codable, CaseIterable, Sendable {
        /// The scale of 1, 2 or 3 that makes the mockup closest to the window's width.
        case automatic
        /// As wide as the window, its height in proportion.
        case fitWidth
        /// One point per pixel.
        case at1x
        /// Two pixels to a point.
        case at2x
        /// Three pixels to a point.
        case at3x

        /// The size the mockup is drawn at, in points.
        ///
        /// - Parameters:
        ///   - pixelSize: The mockup's size in pixels.
        ///   - windowWidth: The window's width in points.
        /// - Returns: The mockup's size in points; zero for a mockup or a window with no width,
        ///   where ``fitWidth`` has nothing to scale to.
        func size(ofMockup pixelSize: CGSize, windowWidth: CGFloat) -> CGSize {
            switch self {
            case .fitWidth:
                guard pixelSize.width > 0, windowWidth > 0 else { return .zero }
                return CGSize(width: windowWidth, height: pixelSize.height * windowWidth / pixelSize.width)
            case .automatic, .at1x, .at2x, .at3x:
                let factor = CGFloat(factor(forMockupWidth: pixelSize.width, windowWidth: windowWidth) ?? 1)
                return CGSize(width: pixelSize.width / factor, height: pixelSize.height / factor)
            }
        }

        /// Pixels to a point: the case's own, or for ``automatic`` the one inferred.
        ///
        /// - Returns: 1, 2 or 3; `nil` for ``fitWidth``, which has no fixed factor.
        func factor(forMockupWidth pixelWidth: CGFloat, windowWidth: CGFloat) -> Int? {
            switch self {
            case .automatic: Self.inferredFactor(mockupWidth: pixelWidth, windowWidth: windowWidth)
            case .fitWidth: nil
            case .at1x: 1
            case .at2x: 2
            case .at3x: 3
            }
        }

        /// The scale a mockup `mockupWidth` pixels wide was exported at, for a window `windowWidth`
        /// points wide: whichever of 1, 2 and 3 brings the mockup's width in points closest to the
        /// window's, the larger on a tie. A window with no width gives 1.
        static func inferredFactor(mockupWidth: CGFloat, windowWidth: CGFloat) -> Int {
            guard windowWidth > 0 else { return 1 }
            // min(by:) keeps the first of equal elements, so listing 3 first breaks ties upward.
            let factors = [3, 2, 1]
            return factors.min { abs(mockupWidth / CGFloat($0) - windowWidth) < abs(mockupWidth / CGFloat($1) - windowWidth) } ?? 1
        }

        /// The name the scale picker shows.
        var title: String {
            switch self {
            case .automatic: "Automatic"
            case .fitWidth: "Fit Width"
            case .at1x: "@1x"
            case .at2x: "@2x"
            case .at3x: "@3x"
            }
        }
    }
#endif
