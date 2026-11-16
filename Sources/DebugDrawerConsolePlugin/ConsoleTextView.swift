#if DEBUG
    import DebugDrawer
    import SwiftUI

    // MARK: - Platform text view wrappers

    // The log is a platform text view rather than SwiftUI rows: it holds up to 2,000 lines,
    // appends each batch without laying the others out again, and selects across lines. Each line
    // is the time in the tertiary color, the issue glyph for an error or fault (drawn from the
    // drawer's own `DebugDrawerIssueGlyph`, so it matches every other plugin's), and the text in
    // the drawer's monospaced code type, debug lines dimmed. The view is clear and sits in a
    // `DebugDrawerCodeBlock`, which gives it the panel's well.

    #if os(macOS)
        import AppKit

        struct ConsoleTextView: NSViewRepresentable {
            let lines: [LogLine]
            @Binding var isFollowing: Bool

            func makeCoordinator() -> Coordinator {
                Coordinator(isFollowing: $isFollowing)
            }

            func makeNSView(context: Context) -> NSScrollView {
                let scrollView = NSTextView.scrollableTextView()
                scrollView.hasVerticalScroller = true
                scrollView.hasHorizontalScroller = false
                scrollView.autohidesScrollers = true
                scrollView.drawsBackground = false

                // scrollableTextView() makes its document view an NSTextView.
                guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
                textView.isEditable = false
                textView.isSelectable = true
                textView.drawsBackground = false
                textView.isRichText = true
                textView.textContainerInset = .zero
                textView.textContainer?.lineFragmentPadding = 0
                textView.textContainer?.widthTracksTextView = true
                textView.textContainer?.lineBreakMode = .byCharWrapping

                context.coordinator.scrollView = scrollView
                NotificationCenter.default.addObserver(
                    context.coordinator,
                    selector: #selector(Coordinator.scrollViewDidScroll(_:)),
                    name: NSScrollView.didLiveScrollNotification,
                    object: scrollView
                )

                return scrollView
            }

            func updateNSView(_ scrollView: NSScrollView, context: Context) {
                guard let textView = scrollView.documentView as? NSTextView,
                      let storage = textView.textStorage else { return }

                let coordinator = context.coordinator
                let newCount = lines.count
                let prevCount = coordinator.renderedLineCount
                let colorScheme = context.environment.colorScheme

                // The glyphs are drawn for one appearance, so a new one redraws every line.
                if colorScheme != coordinator.renderedColorScheme {
                    coordinator.glyphs = ConsoleGlyphs(environment: context.environment)
                    coordinator.renderedColorScheme = colorScheme
                    storage.setAttributedString(buildAttributedString(from: lines, glyphs: coordinator.glyphs, prefixNewline: false))
                    coordinator.renderedLineCount = newCount
                } else if newCount == 0, prevCount > 0 {
                    storage.setAttributedString(NSAttributedString())
                    coordinator.renderedLineCount = 0
                } else if newCount > prevCount {
                    let newLines = Array(lines[prevCount...])
                    let fragment = buildAttributedString(from: newLines, glyphs: coordinator.glyphs, prefixNewline: prevCount > 0)
                    storage.append(fragment)
                    coordinator.renderedLineCount = newCount
                } else if newCount < prevCount {
                    // Ring buffer trimmed — full rebuild
                    storage.setAttributedString(buildAttributedString(from: lines, glyphs: coordinator.glyphs, prefixNewline: false))
                    coordinator.renderedLineCount = newCount
                }

                if isFollowing {
                    DispatchQueue.main.async {
                        coordinator.isProgrammaticScroll = true
                        textView.scrollToEndOfDocument(nil)
                        coordinator.isProgrammaticScroll = false
                    }
                }
            }

            /// The drawer's code type on the Mac: the subheadline's size, monospaced.
            static let codeFont = NSFont.monospacedSystemFont(
                ofSize: NSFont.preferredFont(forTextStyle: .subheadline).pointSize,
                weight: .regular
            )
            private static let dateFormatter: DateFormatter = {
                let formatter = DateFormatter()
                formatter.dateFormat = "HH:mm:ss.SSS"
                return formatter
            }()

            private func buildAttributedString(from lines: [LogLine], glyphs: ConsoleGlyphs?, prefixNewline: Bool) -> NSAttributedString {
                let font = Self.codeFont
                let result = NSMutableAttributedString()
                for (index, line) in lines.enumerated() {
                    if index > 0 || prefixNewline {
                        result.append(NSAttributedString(string: "\n"))
                    }

                    let ts = Self.dateFormatter.string(from: line.timestamp)
                    result.append(NSAttributedString(string: ts + " ", attributes: [
                        .font: font,
                        .foregroundColor: NSColor.tertiaryLabelColor
                    ]))

                    if let severity = line.level.severity, let glyph = glyphs?.attachment(for: severity, font: font) {
                        result.append(glyph)
                        result.append(NSAttributedString(string: " ", attributes: [.font: font]))
                    }

                    result.append(NSAttributedString(string: line.text, attributes: [
                        .font: font,
                        .foregroundColor: line.level == .debug ? NSColor.secondaryLabelColor : NSColor.labelColor
                    ]))
                }
                return result
            }

            final class Coordinator: NSObject {
                var renderedLineCount = 0
                /// The appearance the glyphs were drawn for; nil before the first render.
                var renderedColorScheme: ColorScheme?
                var glyphs: ConsoleGlyphs?
                var isProgrammaticScroll = false
                var isFollowing: Binding<Bool>
                weak var scrollView: NSScrollView?

                init(isFollowing: Binding<Bool>) {
                    self.isFollowing = isFollowing
                }

                // Posted by the clip view, on the main thread.
                @MainActor @objc func scrollViewDidScroll(_: Notification) {
                    guard !isProgrammaticScroll, let scrollView else { return }
                    let clipView = scrollView.contentView
                    let contentHeight = scrollView.documentView?.frame.height ?? 0
                    let scrollOffset = clipView.bounds.origin.y + clipView.bounds.height
                    let atBottom = contentHeight - scrollOffset < 20

                    isFollowing.wrappedValue = atBottom
                }
            }
        }

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

        struct ConsoleTextView: UIViewRepresentable {
            let lines: [LogLine]
            @Binding var isFollowing: Bool

            func makeCoordinator() -> Coordinator {
                Coordinator(isFollowing: $isFollowing)
            }

            func makeUIView(context: Context) -> UITextView {
                let textView = UITextView()
                textView.isEditable = false
                textView.isSelectable = true
                textView.backgroundColor = .clear
                textView.textContainerInset = .zero
                textView.textContainer.lineFragmentPadding = 0
                textView.textContainer.lineBreakMode = .byCharWrapping
                textView.delegate = context.coordinator
                context.coordinator.textView = textView
                return textView
            }

            func updateUIView(_ textView: UITextView, context: Context) {
                let storage = textView.textStorage
                let coordinator = context.coordinator
                let dynamicTypeSize = context.environment.dynamicTypeSize
                let colorScheme = context.environment.colorScheme
                let fonts = ConsoleFonts(dynamicTypeSize: dynamicTypeSize)

                let newCount = lines.count
                let prevCount = coordinator.renderedLineCount

                // The fonts and glyphs are baked into the rendered text, so a new text size or
                // appearance redraws every line.
                if dynamicTypeSize != coordinator.renderedDynamicTypeSize || colorScheme != coordinator.renderedColorScheme {
                    coordinator.glyphs = ConsoleGlyphs(environment: context.environment)
                    storage.setAttributedString(buildAttributedString(from: lines, fonts: fonts, glyphs: coordinator.glyphs, prefixNewline: false))
                    coordinator.renderedLineCount = newCount
                    coordinator.renderedDynamicTypeSize = dynamicTypeSize
                    coordinator.renderedColorScheme = colorScheme
                } else if newCount == 0, prevCount > 0 {
                    storage.setAttributedString(NSAttributedString())
                    coordinator.renderedLineCount = 0
                } else if newCount > prevCount {
                    let newLines = Array(lines[prevCount...])
                    let fragment = buildAttributedString(from: newLines, fonts: fonts, glyphs: coordinator.glyphs, prefixNewline: prevCount > 0)
                    storage.append(fragment)
                    coordinator.renderedLineCount = newCount
                } else if newCount < prevCount {
                    storage.setAttributedString(buildAttributedString(from: lines, fonts: fonts, glyphs: coordinator.glyphs, prefixNewline: false))
                    coordinator.renderedLineCount = newCount
                }

                if isFollowing, storage.length > 0 {
                    coordinator.isProgrammaticScroll = true
                    let range = NSRange(location: storage.length - 1, length: 1)
                    textView.scrollRangeToVisible(range)
                    coordinator.isProgrammaticScroll = false
                }
            }

            private static let dateFormatter: DateFormatter = {
                let formatter = DateFormatter()
                formatter.dateFormat = "HH:mm:ss.SSS"
                return formatter
            }()

            private func buildAttributedString(
                from lines: [LogLine],
                fonts: ConsoleFonts,
                glyphs: ConsoleGlyphs?,
                prefixNewline: Bool
            ) -> NSAttributedString {
                let result = NSMutableAttributedString()
                for (index, line) in lines.enumerated() {
                    if index > 0 || prefixNewline {
                        result.append(NSAttributedString(string: "\n"))
                    }

                    let ts = Self.dateFormatter.string(from: line.timestamp)
                    result.append(NSAttributedString(string: ts + " ", attributes: [
                        .font: fonts.code,
                        .foregroundColor: UIColor.tertiaryLabel
                    ]))

                    if let severity = line.level.severity, let glyph = glyphs?.attachment(for: severity, font: fonts.code) {
                        result.append(glyph)
                        result.append(NSAttributedString(string: " ", attributes: [.font: fonts.code]))
                    }

                    result.append(NSAttributedString(string: line.text, attributes: [
                        .font: fonts.code,
                        .foregroundColor: line.level == .debug ? UIColor.secondaryLabel : UIColor.label
                    ]))
                }
                return result
            }

            final class Coordinator: NSObject, UITextViewDelegate {
                var renderedLineCount = 0
                /// The text size the rendered lines' fonts were made for; nil before the first render.
                var renderedDynamicTypeSize: DynamicTypeSize?
                /// The appearance the glyphs were drawn for; nil before the first render.
                var renderedColorScheme: ColorScheme?
                var glyphs: ConsoleGlyphs?
                var isProgrammaticScroll = false
                var isFollowing: Binding<Bool>
                weak var textView: UITextView?

                init(isFollowing: Binding<Bool>) {
                    self.isFollowing = isFollowing
                }

                func scrollViewDidScroll(_ scrollView: UIScrollView) {
                    guard !isProgrammaticScroll else { return }
                    let contentHeight = scrollView.contentSize.height
                    let scrollOffset = scrollView.contentOffset.y + scrollView.bounds.height
                    let atBottom = contentHeight - scrollOffset < 20
                    isFollowing.wrappedValue = atBottom
                }
            }
        }

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
