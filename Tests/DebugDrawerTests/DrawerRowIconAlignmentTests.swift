// iOS draws the row's controls with UIKit and scales text with Dynamic Type, so these run on the
// iOS simulator; not on Mac Catalyst, as UIKit can't make a window in xctest, which runs package
// tests on Mac Catalyst without an NSApplication.
#if os(iOS) && !targetEnvironment(macCatalyst)
    import DebugDrawer
    import SwiftUI
    import Testing
    import UIKit

    // The row's icon and title are private parts of its layout, so each test hosts the row in a
    // window that is never shown, draws it into a bitmap and finds them by their ink: the icon is
    // the leftmost run of inked columns, the title is what follows it, and each one's line is its
    // first run of inked rows. The icon is a filled circle and each title starts with letters as
    // tall as a capital, so both inks are centred on the cap height when the icon sits on the
    // title's baseline; a symbol like hand.tap reaches above it.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct DrawerRowIconAlignmentTests {
        enum Accessory: String, CaseIterable, CustomTestStringConvertible {
            case toggle, slider, stepper

            var testDescription: String { rawValue }
        }

        @Test(
            "A row's icon sits level with its title, beside it, whatever control the accessory holds",
            arguments: Accessory.allCases, [DynamicTypeSize.large, .accessibility3]
        )
        func iconLevelWithTitle(accessory: Accessory, textSize: DynamicTypeSize) throws {
            let row = Group {
                switch accessory {
                case .toggle:
                    DebugDrawerRow("Highlight Touches", systemImage: "circle.fill", isOn: .constant(true))
                case .slider:
                    DebugDrawerRow("Brightness", systemImage: "circle.fill") {
                        Slider(value: .constant(0.5))
                    }
                case .stepper:
                    DebugDrawerRow("Margin", systemImage: "circle.fill") {
                        Stepper("Margin", value: .constant(0), in: -10...10)
                    }
                }
            }
            let sut = row
                .frame(width: 320, alignment: .leading)
                .padding()
                .background(Color.white)
                .environment(\.dynamicTypeSize, textSize)
            let controller = UIHostingController(rootView: sut)
            controller.safeAreaRegions = []
            let size = controller.sizeThatFits(in: CGSize(width: 352, height: 2000))
            let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
            let window = scene.map(UIWindow.init(windowScene:)) ?? UIWindow()
            window.frame = CGRect(origin: .zero, size: size)
            window.rootViewController = controller
            window.overrideUserInterfaceStyle = .light
            window.isHidden = false
            controller.view.frame = window.bounds
            window.layoutIfNeeded()
            let scale = 2
            let format = UIGraphicsImageRendererFormat()
            format.scale = CGFloat(scale)
            let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
                controller.view.layer.render(in: context.cgContext)
            }
            window.isHidden = true
            let rendered = try #require(image.cgImage)
            let width = rendered.width
            let height = rendered.height
            // Redrawn into RGBA bytes, the first row at the top.
            let context = try #require(CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(rendered, in: CGRect(x: 0, y: 0, width: width, height: height))
            let data = try #require(context.data)
            let pixels = Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: width * height * 4))
            // Ink: a pixel darker than the white background, down to a stepper's pale fill.
            func inked(_ column: Int, _ row: Int) -> Bool {
                let offset = (row * width + column) * 4
                return pixels[offset ..< offset + 3].contains { $0 < 245 }
            }
            // The runs of true values, merging gaps up to `gap` pixels, which lie inside a glyph.
            func runs(_ marks: [Bool], gap: Int) -> [ClosedRange<Int>] {
                var result: [ClosedRange<Int>] = []
                for index in marks.indices where marks[index] {
                    if let last = result.last, index - last.upperBound <= gap {
                        result[result.count - 1] = last.lowerBound ... index
                    } else {
                        result.append(index ... index)
                    }
                }
                return result
            }
            // The icon and the title are at least the row's 8-point spacing apart; a symbol's own
            // gaps are narrower than 4.
            let columns = runs((0 ..< width).map { column in (0 ..< height).contains { row in inked(column, row) } }, gap: 4 * scale)
            let iconColumns = try #require(columns.first)
            // The title's first letters, past the icon: narrow enough to miss an accessory at the
            // trailing edge, and above one stacked below the title.
            let titleStart = iconColumns.upperBound + 4 * scale
            let titleColumns = titleStart ... min(width - 1, titleStart + 16 * scale)
            let iconLines = runs((0 ..< height).map { row in iconColumns.contains { column in inked(column, row) } }, gap: 2 * scale)
            let titleLines = runs((0 ..< height).map { row in titleColumns.contains { column in inked(column, row) } }, gap: 2 * scale)
            let icon = try #require(iconLines.first)
            let title = try #require(titleLines.first)
            let tolerance: CGFloat = 2

            let actual = abs(CGFloat(icon.lowerBound + icon.upperBound) - CGFloat(title.lowerBound + title.upperBound)) / 2 / CGFloat(scale)

            #expect(actual <= tolerance, "icon rows \(icon), title rows \(title), at \(scale)x")
            #expect(iconLines.count == 1, "the icon column holds only the icon: \(iconLines)")
            if textSize.isAccessibilitySize {
                // Stacked: the accessory starts at the leading edge, below the title.
                #expect(titleLines.count >= 2, "the accessory sits below the title: \(titleLines)")
            } else {
                #expect(titleLines.count == 1, "the accessory sits beside the title: \(titleLines)")
            }
        }
    }
#endif
