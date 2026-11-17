#if DEBUG
    import DebugDrawer
    import SwiftUI

    #if os(macOS)
        import AppKit

        /// The issue glyphs a log line can carry, drawn once for an appearance from the drawer's
        /// `DebugDrawerIssueGlyph`, to set into the text as attachments.
        @MainActor
        struct ConsoleGlyphs {
            private let images: [DebugDrawerIssueGlyph.Severity: NSImage]

            init(environment: EnvironmentValues) {
                var images: [DebugDrawerIssueGlyph.Severity: NSImage] = [:]
                for severity in [DebugDrawerIssueGlyph.Severity.error, .warning] {
                    let renderer = ImageRenderer(content: DebugDrawerIssueGlyph(severity)
                        .environment(\.colorScheme, environment.colorScheme))
                    renderer.scale = environment.displayScale
                    images[severity] = renderer.nsImage
                }
                self.images = images
            }

            /// The glyph as text, centered on the font's capitals.
            func attachment(for severity: DebugDrawerIssueGlyph.Severity, font: NSFont) -> NSAttributedString? {
                guard let image = images[severity] else { return nil }
                let attachment = NSTextAttachment()
                attachment.image = image
                attachment.bounds = CGRect(
                    x: 0,
                    y: (font.capHeight - image.size.height) / 2,
                    width: image.size.width,
                    height: image.size.height
                )
                return NSAttributedString(attachment: attachment)
            }
        }

    #elseif os(iOS)
        import UIKit

        /// The issue glyphs a log line can carry, drawn once for an appearance and text size from
        /// the drawer's `DebugDrawerIssueGlyph`, to set into the text as attachments.
        @MainActor
        struct ConsoleGlyphs {
            private let images: [DebugDrawerIssueGlyph.Severity: UIImage]

            init(environment: EnvironmentValues) {
                var images: [DebugDrawerIssueGlyph.Severity: UIImage] = [:]
                for severity in [DebugDrawerIssueGlyph.Severity.error, .warning] {
                    let renderer = ImageRenderer(content: DebugDrawerIssueGlyph(severity)
                        .environment(\.colorScheme, environment.colorScheme)
                        .environment(\.dynamicTypeSize, environment.dynamicTypeSize))
                    renderer.scale = environment.displayScale
                    images[severity] = renderer.uiImage
                }
                self.images = images
            }

            /// The glyph as text, centered on the font's capitals.
            func attachment(for severity: DebugDrawerIssueGlyph.Severity, font: UIFont) -> NSAttributedString? {
                guard let image = images[severity] else { return nil }
                let attachment = NSTextAttachment()
                attachment.image = image
                attachment.bounds = CGRect(
                    x: 0,
                    y: (font.capHeight - image.size.height) / 2,
                    width: image.size.width,
                    height: image.size.height
                )
                return NSAttributedString(attachment: attachment)
            }
        }
    #endif
#endif
