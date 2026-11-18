// Views render on the Mac; the snapshot packages are linked on Apple platforms only.
#if os(macOS)
    import AppKit
    @testable import DebugDrawerDeepLinkPlugin
    import Foundation
    import SnapshotTesting
    import SwiftUI
    import Testing

    /// A form state the open results add: each result an opened URL can have, and no presets.
    enum DeepLinkOpenState: String, CaseIterable, Sendable {
        case handled
        case notHandled
        case couldNotOpen
        case noPresets
    }

    // At 316 points, the width of the drawer on an iPad and the narrowest it gets, hosted in a
    // window that is never shown and drawn into a bitmap at a fixed 2x scale in the appearance the
    // test asks for, as DeepLinkSnapshotTests does. macOS doesn't scale text with Dynamic Type, so
    // the Mac pins light and dark only.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct DeepLinkResultSnapshotTests {
        // The share of pixels a hosted text-field snapshot must match: the AppKit field's host
        // sometimes measures it 2 pt short (DD-182), which moves only the field's text.
        private static let textFieldPrecision: Float = 0.99

        @Test(
            "After an open, the result row says handled, not handled or the system's error; with no presets, Presets says how to add them",
            arguments: DeepLinkOpenState.allCases, [ColorScheme.light, .dark]
        )
        func results(state: DeepLinkOpenState, colorScheme: ColorScheme) throws {
            let url = "debugdrawer-example://orders/42"
            let presets = try [DeepLinkPreset("DebugDrawer Example", url: #require(URL(string: "debugdrawer-example://")))]
            let outcome: DeepLinkOutcome? = switch state {
            case .handled: .handled(url)
            case .notHandled: .notHandled(url)
            case .couldNotOpen: .couldNotOpen(url, reason: "no installed app opens debugdrawer-example: URLs")
            case .noPresets: nil
            }
            let sut = DeepLinkForm(
                urlText: .constant(state == .noPresets ? "" : url),
                outcome: outcome,
                presets: state == .noPresets ? [] : presets,
                history: state == .noPresets ? [] : [url],
                onOpen: { _ in },
                onContinue: { _ in },
                onClear: {}
            )

            let host = NSHostingView(rootView: sut
                .environment(\.locale, Locale(identifier: "en_US"))
                .frame(width: 316, alignment: .leading)
                .padding()
                .background(.background))
            host.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
            let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: true)
            window.contentView = host
            host.frame = CGRect(origin: .zero, size: host.fittingSize)
            host.layoutSubtreeIfNeeded()
            let bitmap = try #require(NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(host.bounds.width) * 2, pixelsHigh: Int(host.bounds.height) * 2,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
            ))
            bitmap.size = host.bounds.size
            host.cacheDisplay(in: host.bounds, to: bitmap)

            let actual = NSImage(size: host.bounds.size)
            actual.addRepresentation(bitmap)

            // The AppKit text field's host sometimes measures it 2 pt short (DD-182), which moves its text.
            assertSnapshot(
                of: actual, as: .image(precision: Self.textFieldPrecision, perceptualPrecision: 0.98),
                named: "\(state.rawValue)-\(colorScheme == .dark ? "dark" : "light")"
            )
        }
    }
#endif
