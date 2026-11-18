import CoreGraphics

extension CGFloat {
    /// How many times larger the platform's text styles are than iOS's, for sizes laid out beside
    /// text in iOS points (an icon column, a label column, the panel's width). `@ScaledMetric`
    /// follows Dynamic Type but not the platform's base sizes, and tvOS's, read from across a
    /// room, are about twice iOS's.
    static var debugDrawerTextScale: CGFloat {
        #if os(tvOS)
            2
        #else
            1
        #endif
    }
}

import SwiftUI

#if os(macOS)
    import AppKit
#elseif canImport(UIKit)
    // Mac Catalyst takes this branch too: a Catalyst app is a UIKit app and can't import AppKit.
    import UIKit
#endif
#if os(watchOS)
    import WatchKit
#endif

/// Puts `string` on the general pasteboard, replacing what was there.
///
/// Unavailable on tvOS and watchOS, which have no pasteboard: a call there fails to compile
/// rather than silently copying nothing. In release builds it does nothing.
///
/// - Parameter string: The text to copy.
@available(tvOS, unavailable)
@available(watchOS, unavailable)
public func debugDrawerCopyToClipboard(_ string: String) {
    #if DEBUG && os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    #elseif DEBUG && (os(iOS) || os(visionOS))
        // Under Mac Catalyst, UIPasteboard.general is the Mac's general pasteboard.
        UIPasteboard.general.string = string
    #endif
}

#if DEBUG
    /// Whether the user turned on Reduce Motion in the system's accessibility settings, for code
    /// outside a view, which can't read `\.accessibilityReduceMotion`.
    @MainActor var debugDrawerSystemReduceMotion: Bool {
        #if os(macOS)
            NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        #elseif os(iOS) || os(visionOS) || os(tvOS)
            // Under Mac Catalyst, UIAccessibility reads the Mac's Reduce Motion setting.
            UIAccessibility.isReduceMotionEnabled
        #elseif os(watchOS)
            WKAccessibilityIsReduceMotionEnabled()
        #else
            false
        #endif
    }

    extension View {
        /// Lets the user select and copy the text, where the platform can: tvOS and watchOS have
        /// neither text selection nor a pasteboard, so there the text is only shown.
        @ViewBuilder
        func debugDrawerTextSelection() -> some View {
            #if os(tvOS) || os(watchOS)
                self
            #else
                textSelection(.enabled)
            #endif
        }
    }
#endif

#if os(macOS)
    /// The platform's image type: `NSImage` on the Mac, `UIImage` elsewhere.
    public typealias PlatformImage = NSImage
    /// The platform's color type: `NSColor` on the Mac, `UIColor` elsewhere.
    typealias PlatformColor = NSColor
#elseif os(iOS) || os(visionOS) || os(tvOS) || os(watchOS)
    // UIKit's types on Mac Catalyst too, whose views and pasteboard are UIKit's.
    /// The platform's image type: `UIImage` here, `NSImage` on the Mac.
    public typealias PlatformImage = UIImage
    /// The platform's color type: `UIColor` here, `NSColor` on the Mac.
    typealias PlatformColor = UIColor
#endif
