#if DEBUG
    import SwiftUI

    #if os(macOS)
        import AppKit
    #elseif os(iOS) || os(visionOS)
        import UIKit
    #endif

    /// Cross-platform clipboard helper.
    public func debugDrawerCopyToClipboard(_ string: String) {
        #if os(macOS)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(string, forType: .string)
        #elseif os(iOS) || os(visionOS)
            UIPasteboard.general.string = string
        #endif
    }

    /// Cross-platform image copy.
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
        #elseif os(iOS) || os(visionOS)
            UIAccessibility.isReduceMotionEnabled
        #else
            false
        #endif
    }

    #if os(macOS)
        public typealias PlatformImage = NSImage
        public typealias PlatformColor = NSColor
        public typealias PlatformFont = NSFont
    #elseif os(iOS) || os(visionOS)
        public typealias PlatformImage = UIImage
        public typealias PlatformColor = UIColor
        public typealias PlatformFont = UIFont
    #endif
#endif
