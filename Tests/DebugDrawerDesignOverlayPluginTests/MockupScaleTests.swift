#if DEBUG
    import CoreGraphics
    @testable import DebugDrawerDesignOverlayPlugin
    import Testing

    @Suite
    struct MockupScaleTests {
        @Test("An iPhone's @3x export is inferred as @3x for its 430-point window, and drawn 430 by 932 points")
        func inferredThree() {
            let pixels = CGSize(width: 1290, height: 2796)
            let expected = CGSize(width: 430, height: 932)

            let actual = MockupScale.automatic.size(ofMockup: pixels, windowWidth: 430)

            #expect(MockupScale.inferredFactor(mockupWidth: 1290, windowWidth: 430) == 3)
            #expect(actual == expected)
        }

        @Test("A 13-inch iPad's @2x export is inferred as @2x for its 1032-point window")
        func inferredTwo() {
            let pixels = CGSize(width: 2064, height: 2752)
            let expected = CGSize(width: 1032, height: 1376)

            let actual = MockupScale.automatic.size(ofMockup: pixels, windowWidth: 1032)

            #expect(MockupScale.inferredFactor(mockupWidth: 2064, windowWidth: 1032) == 2)
            #expect(actual == expected)
        }

        @Test("A mockup as wide as the window in pixels is @1x, and one far narrower still is")
        func inferredOne() {
            let sameWidth = MockupScale.inferredFactor(mockupWidth: 800, windowWidth: 800)
            let narrower = MockupScale.inferredFactor(mockupWidth: 100, windowWidth: 800)

            #expect(sameWidth == 1)
            #expect(narrower == 1)
        }

        @Test("A mockup far wider than three times the window is @3x, the largest scale")
        func inferredBeyondThree() {
            let actual = MockupScale.inferredFactor(mockupWidth: 5000, windowWidth: 400)

            #expect(actual == 3)
        }

        @Test("The nearer scale wins, and halfway between two goes to the larger")
        func ties() {
            // 500 points at @3x is 100 off; 750 at @2x is 150 off.
            let nearer = MockupScale.inferredFactor(mockupWidth: 1500, windowWidth: 600)
            // 1200 / 2 = 600 and 1200 / 3 = 400 are both 100 from 500 points.
            let tie = MockupScale.inferredFactor(mockupWidth: 1200, windowWidth: 500)
            // 900 / 1 and 900 / 2 are both 225 from 675 points.
            let lowerTie = MockupScale.inferredFactor(mockupWidth: 900, windowWidth: 675)

            #expect(nearer == 3)
            #expect(tie == 3)
            #expect(lowerTie == 2)
        }

        @Test("A window with no width infers @1x")
        func noWindow() {
            let actual = MockupScale.inferredFactor(mockupWidth: 1290, windowWidth: 0)

            #expect(actual == 1)
        }

        @Test("Fit Width draws the mockup as wide as the window, its height in proportion")
        func fitWidth() {
            let pixels = CGSize(width: 1290, height: 2796)
            let windowWidth: CGFloat = 600
            let expected = CGSize(width: windowWidth, height: pixels.height * windowWidth / pixels.width)

            let actual = MockupScale.fitWidth.size(ofMockup: pixels, windowWidth: 600)

            #expect(actual == expected)
            #expect(MockupScale.fitWidth.factor(forMockupWidth: 1290, windowWidth: 600) == nil)
        }

        @Test("Fit Width of an empty mockup or into a window with no width is zero")
        func fitWidthEmpty() {
            let empty = MockupScale.fitWidth.size(ofMockup: .zero, windowWidth: 600)
            let noWindow = MockupScale.fitWidth.size(ofMockup: CGSize(width: 10, height: 10), windowWidth: 0)

            #expect(empty == .zero)
            #expect(noWindow == .zero)
        }

        @Test("@1x, @2x and @3x divide the pixels by 1, 2 and 3 whatever the window's width")
        func fixedScales() {
            let pixels = CGSize(width: 1200, height: 600)
            let expected = [CGSize(width: 1200, height: 600), CGSize(width: 600, height: 300), CGSize(width: 400, height: 200)]

            let actual = [MockupScale.at1x, .at2x, .at3x].map { $0.size(ofMockup: pixels, windowWidth: 375) }

            #expect(actual == expected)
            #expect([MockupScale.at1x, .at2x, .at3x].map { $0.factor(forMockupWidth: 1200, windowWidth: 375) } == [1, 2, 3])
        }

        @Test("A one-pixel mockup is a point at @1x and a third of one at @3x")
        func onePixel() {
            let pixel = CGSize(width: 1, height: 1)

            let atOne = MockupScale.at1x.size(ofMockup: pixel, windowWidth: 100)
            let atThree = MockupScale.at3x.size(ofMockup: pixel, windowWidth: 100)

            #expect(atOne == CGSize(width: 1, height: 1))
            #expect(atThree == CGSize(width: 1.0 / 3, height: 1.0 / 3))
        }

        @Test("Inference picks the scale nearest the window, the same as trying each one by hand, for widths from 1 to 4000 pixels")
        func inferenceMatchesNaive() {
            let windowWidths: [CGFloat] = [320, 375, 430, 768, 1032, 1440]
            var mismatches: [String] = []

            for windowWidth in windowWidths {
                for pixelWidth in stride(from: CGFloat(1), through: 4000, by: 7) {
                    let distances = [1, 2, 3].map { (factor: $0, distance: abs(pixelWidth / CGFloat($0) - windowWidth)) }
                    let best = distances.map(\.distance).min() ?? 0
                    let expected = distances.filter { $0.distance == best }.map(\.factor).max() ?? 1
                    let actual = MockupScale.inferredFactor(mockupWidth: pixelWidth, windowWidth: windowWidth)
                    if actual != expected { mismatches.append("\(pixelWidth) in \(windowWidth): \(actual), not \(expected)") }
                }
            }

            #expect(mismatches.isEmpty)
        }
    }
#endif
