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

#if DEBUG
    import SwiftUI

    #if os(macOS)
        import AppKit
    #elseif os(iOS) || os(visionOS) || os(tvOS)
        import UIKit
    #endif

    /// Cross-platform clipboard helper.
    ///
    /// Unavailable on tvOS, which has no pasteboard: a call there fails to compile rather than
    /// silently copying nothing.
    @available(tvOS, unavailable)
    public func debugDrawerCopyToClipboard(_ string: String) {
        #if os(macOS)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(string, forType: .string)
        #elseif os(iOS) || os(visionOS)
            UIPasteboard.general.string = string
        #endif
    }

    /// Cross-platform image copy.
    ///
    /// Unavailable on tvOS, which has no pasteboard.
    @available(tvOS, unavailable)
    public func debugDrawerCopyImageToClipboard(_ image: PlatformImage) {
        #if os(macOS)
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.writeObjects([image])
        #elseif os(iOS) || os(visionOS)
            UIPasteboard.general.image = image
        #endif
    }

    /// Whether the user turned on Reduce Motion in the system's accessibility settings, for code
    /// outside a view, which can't read `\.accessibilityReduceMotion`.
    @MainActor var debugDrawerSystemReduceMotion: Bool {
        #if os(macOS)
            NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        #elseif os(iOS) || os(visionOS) || os(tvOS)
            UIAccessibility.isReduceMotionEnabled
        #else
            false
        #endif
    }

    extension View {
        /// Lets the user select and copy the text, where the platform can: tvOS has neither text
        /// selection nor a pasteboard, so there the text is only shown.
        @ViewBuilder
        func debugDrawerTextSelection() -> some View {
            #if os(tvOS)
                self
            #else
                textSelection(.enabled)
            #endif
        }

        /// The drawer's text field look: a small rounded border, or on tvOS the system's own field,
        /// which grows when focused and edits in a full-screen keyboard.
        @ViewBuilder
        func debugDrawerTextFieldStyle() -> some View {
            #if os(tvOS)
                self
            #else
                textFieldStyle(.roundedBorder).controlSize(.small)
            #endif
        }
    }

    #if os(macOS)
        public typealias PlatformImage = NSImage
        public typealias PlatformColor = NSColor
        public typealias PlatformFont = NSFont
    #elseif os(iOS) || os(visionOS) || os(tvOS)
        public typealias PlatformImage = UIImage
        public typealias PlatformColor = UIColor
        public typealias PlatformFont = UIFont
    #endif
#endif
