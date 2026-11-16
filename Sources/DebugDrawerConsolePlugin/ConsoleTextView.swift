#if DEBUG
    import SwiftUI

    // MARK: - Platform text view wrappers

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
                scrollView.drawsBackground = true
                scrollView.backgroundColor = NSColor.black.withAlphaComponent(0.3)

                // scrollableTextView() makes its document view an NSTextView.
                guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
                textView.isEditable = false
                textView.isSelectable = true
                textView.drawsBackground = false
                textView.isRichText = true
                textView.textContainerInset = NSSize(width: 4, height: 4)
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

                let newCount = lines.count
                let prevCount = context.coordinator.renderedLineCount

                if newCount == 0, prevCount > 0 {
                    storage.setAttributedString(NSAttributedString())
                    context.coordinator.renderedLineCount = 0
                } else if newCount > prevCount {
                    let newLines = Array(lines[prevCount...])
                    let fragment = buildAttributedString(from: newLines, prefixNewline: prevCount > 0)
                    storage.append(fragment)
                    context.coordinator.renderedLineCount = newCount
                } else if newCount < prevCount {
                    // Ring buffer trimmed — full rebuild
                    storage.setAttributedString(buildAttributedString(from: lines, prefixNewline: false))
                    context.coordinator.renderedLineCount = newCount
                }

                if isFollowing {
                    let coordinator = context.coordinator
                    DispatchQueue.main.async {
                        coordinator.isProgrammaticScroll = true
                        textView.scrollToEndOfDocument(nil)
                        coordinator.isProgrammaticScroll = false
                    }
                }
            }

            private static let monoFont = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
            private static let smallMonoFont = NSFont.monospacedSystemFont(ofSize: 9, weight: .regular)
            private static let badgeFont = NSFont.monospacedSystemFont(ofSize: 8, weight: .bold)
            private static let timestampColor = NSColor.tertiaryLabelColor
            private static let dateFormatter: DateFormatter = {
                let formatter = DateFormatter()
                formatter.dateFormat = "HH:mm:ss.SSS"
                return formatter
            }()

            private func buildAttributedString(from lines: [LogLine], prefixNewline: Bool) -> NSAttributedString {
                let result = NSMutableAttributedString()
                for (index, line) in lines.enumerated() {
                    if index > 0 || prefixNewline {
                        result.append(NSAttributedString(string: "\n"))
                    }

                    let ts = Self.dateFormatter.string(from: line.timestamp)
                    result.append(NSAttributedString(string: ts + " ", attributes: [
                        .font: Self.smallMonoFont,
                        .foregroundColor: Self.timestampColor
                    ]))

                    if let badge = line.level.label {
                        result.append(NSAttributedString(string: badge + " ", attributes: [
                            .font: Self.badgeFont,
                            .foregroundColor: nsColor(for: line.level)
                        ]))
                    }

                    if line.source == .oslog {
                        result.append(NSAttributedString(string: "⌘ ", attributes: [
                            .font: Self.smallMonoFont,
                            .foregroundColor: Self.timestampColor
                        ]))
                    }

                    result.append(NSAttributedString(string: line.text, attributes: [
                        .font: Self.monoFont,
                        .foregroundColor: nsColor(for: line.level)
                    ]))
                }
                return result
            }

            private func nsColor(for level: LogLine.Level) -> NSColor {
                switch level {
                case .debug: .secondaryLabelColor
                case .info: .labelColor
                case .notice: .labelColor
                case .error: .systemRed
                case .fault: .systemRed
                }
            }

            final class Coordinator: NSObject {
                var renderedLineCount = 0
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
                textView.backgroundColor = UIColor.black.withAlphaComponent(0.3)
                textView.textContainerInset = UIEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)
                textView.textContainer.lineBreakMode = .byCharWrapping
                textView.delegate = context.coordinator
                context.coordinator.textView = textView
                return textView
            }

            func updateUIView(_ textView: UITextView, context: Context) {
                let storage = textView.textStorage
                let dynamicTypeSize = context.environment.dynamicTypeSize
                let fonts = ConsoleFonts(dynamicTypeSize: dynamicTypeSize)

                let newCount = lines.count
                let prevCount = context.coordinator.renderedLineCount

                // The fonts are baked into the rendered text, so a new text size redraws every line.
                if dynamicTypeSize != context.coordinator.renderedDynamicTypeSize {
                    storage.setAttributedString(buildAttributedString(from: lines, fonts: fonts, prefixNewline: false))
                    context.coordinator.renderedLineCount = newCount
                    context.coordinator.renderedDynamicTypeSize = dynamicTypeSize
                } else if newCount == 0, prevCount > 0 {
                    storage.setAttributedString(NSAttributedString())
                    context.coordinator.renderedLineCount = 0
                } else if newCount > prevCount {
                    let newLines = Array(lines[prevCount...])
                    let fragment = buildAttributedString(from: newLines, fonts: fonts, prefixNewline: prevCount > 0)
                    storage.append(fragment)
                    context.coordinator.renderedLineCount = newCount
                } else if newCount < prevCount {
                    storage.setAttributedString(buildAttributedString(from: lines, fonts: fonts, prefixNewline: false))
                    context.coordinator.renderedLineCount = newCount
                }

                if isFollowing, storage.length > 0 {
                    context.coordinator.isProgrammaticScroll = true
                    let range = NSRange(location: storage.length - 1, length: 1)
                    textView.scrollRangeToVisible(range)
                    context.coordinator.isProgrammaticScroll = false
                }
            }

            private static let timestampColor = UIColor.tertiaryLabel
            private static let dateFormatter: DateFormatter = {
                let formatter = DateFormatter()
                formatter.dateFormat = "HH:mm:ss.SSS"
                return formatter
            }()

            private func buildAttributedString(from lines: [LogLine], fonts: ConsoleFonts, prefixNewline: Bool) -> NSAttributedString {
                let result = NSMutableAttributedString()
                for (index, line) in lines.enumerated() {
                    if index > 0 || prefixNewline {
                        result.append(NSAttributedString(string: "\n"))
                    }

                    let ts = Self.dateFormatter.string(from: line.timestamp)
                    result.append(NSAttributedString(string: ts + " ", attributes: [
                        .font: fonts.small,
                        .foregroundColor: Self.timestampColor
                    ]))

                    if let badge = line.level.label {
                        result.append(NSAttributedString(string: badge + " ", attributes: [
                            .font: fonts.badge,
                            .foregroundColor: uiColor(for: line.level)
                        ]))
                    }

                    if line.source == .oslog {
                        result.append(NSAttributedString(string: "⌘ ", attributes: [
                            .font: fonts.small,
                            .foregroundColor: Self.timestampColor
                        ]))
                    }

                    result.append(NSAttributedString(string: line.text, attributes: [
                        .font: fonts.text,
                        .foregroundColor: uiColor(for: line.level)
                    ]))
                }
                return result
            }

            private func uiColor(for level: LogLine.Level) -> UIColor {
                switch level {
                case .debug: .secondaryLabel
                case .info: .label
                case .notice: .label
                case .error: .systemRed
                case .fault: .systemRed
                }
            }

            final class Coordinator: NSObject, UITextViewDelegate {
                var renderedLineCount = 0
                /// The text size the rendered lines' fonts were made for; nil before the first render.
                var renderedDynamicTypeSize: DynamicTypeSize?
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
    #endif
#endif
