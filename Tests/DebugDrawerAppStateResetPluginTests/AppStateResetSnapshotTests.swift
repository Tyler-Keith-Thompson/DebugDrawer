// Views render on the Mac; the snapshot packages are linked on Apple platforms only.
#if os(macOS)
    import AppKit
    @testable import DebugDrawerAppStateResetPlugin
    @testable import DebugDrawerAppStateReset
    import SnapshotTesting
    import SwiftUI
    import Testing

    // ImageRenderer draws AppKit-backed controls (the checkboxes, switches and buttons) as
    // placeholders, so the tests host the view in a window that is never shown and draw it into a
    // bitmap at a fixed 2x scale, in the appearance the test asks for. macOS doesn't scale text with
    // Dynamic Type, so the Mac pins light and dark only. Sizes are written in en_US.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct AppStateResetSnapshotTests {
        @Test("Every category with its checkbox and summary, the DebugDrawer switch, Refresh and Reset…", arguments: [ColorScheme.light, .dark])
        func ready(colorScheme: ColorScheme) throws {
            let sut = AppStateResetView(
                state: .ready(ResetPlanFixture.plan), selection: .constant([.userDefaults, .files, .caches, .cookies]),
                includesDebugDrawer: .constant(false), restartStyle: .relaunch, refresh: {}, reset: { _ in }
            )
            let host = NSHostingView(rootView: sut
                .environment(\.locale, Locale(identifier: "en_US"))
                .frame(width: 360, alignment: .leading)
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

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "\(colorScheme)")
        }

        @Test("The confirmation: each selected category's lines, then Cancel, Reset and Reset and Relaunch", arguments: [ColorScheme.light, .dark])
        func confirmation(colorScheme: ColorScheme) throws {
            let sut = ResetConfirmationView(
                plan: ResetPlanFixture.plan, categories: [.userDefaults, .keychain, .files, .cookies], restartStyle: .relaunch,
                cancel: {}, reset: {}, resetAndRestart: {}
            )
            // A sheet's height: the list scrolls in it.
            let host = NSHostingView(rootView: sut
                .environment(\.locale, Locale(identifier: "en_US"))
                .frame(width: 440, height: 560, alignment: .topLeading)
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

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "\(colorScheme)")
        }

        @Test("Opened rows list each line with its size or class, as a tap on Show Details leaves them", arguments: [ColorScheme.light, .dark])
        func openedRows(colorScheme: ColorScheme) throws {
            let plan = ResetPlanFixture.plan
            let sut = VStack(alignment: .leading, spacing: 0) {
                ForEach([AppStateReset.Category.files, .keychain, .cookies]) { category in
                    ResetCategoryRow(
                        category: category, summary: plan.summary(of: category), lines: plan.lines(of: category), problem: nil,
                        isSelected: .constant(category != .cookies), isExpanded: true
                    )
                }
            }
            let host = NSHostingView(rootView: sut
                .environment(\.locale, Locale(identifier: "en_US"))
                .frame(width: 360, alignment: .leading)
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

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "\(colorScheme)")
        }

        @Test("After a reset: what was cleared, a file that wasn't with why, and the restart held for it", arguments: [ColorScheme.light, .dark])
        func finished(colorScheme: ColorScheme) throws {
            var plan = ResetPlanFixture.plan
            plan.defaults = []
            plan.files = [plan.files[0]]
            let result = ResetResult(outcomes: [
                .userDefaults: .cleared(4),
                .files: .failed(cleared: 2, failures: [.file("Documents/Drafts", reason: "You don't have permission to delete it.")]),
                .urlCache: .cleared(1)
            ])
            let sut = AppStateResetView(
                state: .finished(plan, result, .heldForFailures), selection: .constant([.userDefaults, .files, .urlCache]),
                includesDebugDrawer: .constant(false), restartStyle: .relaunch, refresh: {}, reset: { _ in }
            )
            let host = NSHostingView(rootView: sut
                .environment(\.locale, Locale(identifier: "en_US"))
                .frame(width: 360, alignment: .leading)
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

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "\(colorScheme)")
        }
    }
#endif
