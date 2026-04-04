#if DEBUG
    import SwiftUI

    #if os(macOS)
        import AppKit
    #elseif os(iOS)
        import UIKit
    #endif

    /// Cross-platform clipboard helper.
    public func debugDrawerCopyToClipboard(_ string: String) {
        #if os(macOS)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(string, forType: .string)
        #elseif os(iOS)
            UIPasteboard.general.string = string
        #endif
    }

    /// Cross-platform image copy.
    public func debugDrawerCopyImageToClipboard(_ image: PlatformImage) {
        #if os(macOS)
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.writeObjects([image])
        #elseif os(iOS)
            UIPasteboard.general.image = image
        #endif
    }

    #if os(macOS)
        public typealias PlatformImage = NSImage
        public typealias PlatformColor = NSColor
        public typealias PlatformFont = NSFont
    #elseif os(iOS)
        public typealias PlatformImage = UIImage
        public typealias PlatformColor = UIColor
        public typealias PlatformFont = UIFont
    #endif
#endif
