#if DEBUG
    import DebugDrawer
    import SwiftUI

    // MARK: - Platform text view wrappers

    // The log is a platform text view rather than SwiftUI rows: it holds up to 2,000 lines,
    // appends each batch without laying the others out again, and selects across lines. Each line
    // is the time in the tertiary color, the issue glyph for an error or fault (drawn from the
    // drawer's own `DebugDrawerIssueGlyph`, so it matches every other plugin's), the subsystem and
    // category, short and in the tertiary color, and the text in the drawer's monospaced code
    // type, debug lines dimmed. The view is clear and sits in a `DebugDrawerCodeBlock`, which
    // gives it the panel's well. A line's context menu (the edit menu on iOS) mutes its subsystem
    // or category, or shows the lines from it on.

    #if os(macOS)
        import AppKit

        struct ConsoleTextView: NSViewRepresentable {
            let lines: [LogLine]
            @Binding var isFollowing: Bool
            /// Runs what a line's context menu offers.
            var perform: (ConsoleLineAction) -> Void = { _ in }

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
                textView.delegate = context.coordinator

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
                coordinator.perform = perform
                let colorScheme = context.environment.colorScheme

                // The glyphs are drawn for one appearance, so a new one redraws every line.
                let update: ConsoleRenderedLines.Update
                if colorScheme != coordinator.renderedColorScheme {
                    coordinator.glyphs = ConsoleGlyphs(environment: context.environment)
                    coordinator.renderedColorScheme = colorScheme
                    update = .redraw
                } else {
                    update = coordinator.rendered.update(to: lines)
                }

                switch update {
                case .none:
                    break
                case .redraw:
                    let text = buildAttributedString(from: lines, glyphs: coordinator.glyphs, prefixNewline: false, offset: 0)
                    storage.setAttributedString(text.string)
                    coordinator.rendered.redrew(lines, starts: text.starts)
                case let .extend(dropping, appending):
                    storage.beginEditing()
                    if dropping > 0 {
                        storage.deleteCharacters(in: NSRange(location: 0, length: coordinator.rendered.length(ofFirst: dropping)))
                    }
                    let appended = Array(lines[appending...])
                    let text = buildAttributedString(from: appended, glyphs: coordinator.glyphs, prefixNewline: true, offset: storage.length)
                    storage.append(text.string)
                    storage.endEditing()
                    coordinator.rendered.extended(dropping: dropping, appended: appended, appendedStarts: text.starts)
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

            /// `lines` as text, a newline between each and, with `prefixNewline`, one before the
            /// first, with where each line starts once the text is placed at `offset`.
            private func buildAttributedString(
                from lines: [LogLine],
                glyphs: ConsoleGlyphs?,
                prefixNewline: Bool,
                offset: Int
            ) -> ConsoleDrawnText {
                let font = Self.codeFont
                let result = NSMutableAttributedString()
                var starts: [Int] = []
                starts.reserveCapacity(lines.count)
                for (index, line) in lines.enumerated() {
                    if index > 0 || prefixNewline {
                        result.append(NSAttributedString(string: "\n"))
                    }
                    starts.append(offset + result.length)

                    let ts = Self.dateFormatter.string(from: line.timestamp)
                    result.append(NSAttributedString(string: ts + " ", attributes: [
                        .font: font,
                        .foregroundColor: NSColor.tertiaryLabelColor
                    ]))

                    if let severity = line.level.severity, let glyph = glyphs?.attachment(for: severity, font: font) {
                        result.append(glyph)
                        result.append(NSAttributedString(string: " ", attributes: [.font: font]))
                    }

                    if let origin = line.shownOrigin {
                        result.append(NSAttributedString(string: origin + " ", attributes: [
                            .font: font,
                            .foregroundColor: NSColor.tertiaryLabelColor
                        ]))
                    }

                    result.append(NSAttributedString(string: line.text, attributes: [
                        .font: font,
                        .foregroundColor: line.level == .debug ? NSColor.secondaryLabelColor : NSColor.labelColor
                    ]))
                }
                return ConsoleDrawnText(string: result, starts: starts)
            }

            @MainActor
            final class Coordinator: NSObject, NSTextViewDelegate {
                /// The lines the text shows, and where each starts.
                var rendered = ConsoleRenderedLines()
                /// The appearance the glyphs were drawn for; nil before the first render.
                var renderedColorScheme: ColorScheme?
                var glyphs: ConsoleGlyphs?
                var isProgrammaticScroll = false
                var isFollowing: Binding<Bool>
                /// Runs what a line's context menu offers.
                var perform: (ConsoleLineAction) -> Void = { _ in }
                /// The actions of the context menu last shown, by the items' tags.
                private var menuActions: [ConsoleLineAction] = []
                weak var scrollView: NSScrollView?

                init(isFollowing: Binding<Bool>) {
                    self.isFollowing = isFollowing
                }

                // Posted by the clip view, on the main thread.
                @objc func scrollViewDidScroll(_: Notification) {
                    guard !isProgrammaticScroll, let scrollView else { return }
                    let clipView = scrollView.contentView
                    let contentHeight = scrollView.documentView?.frame.height ?? 0
                    let scrollOffset = clipView.bounds.origin.y + clipView.bounds.height
                    let atBottom = contentHeight - scrollOffset < 20

                    isFollowing.wrappedValue = atBottom
                }

                /// The text view's context menu, with the actions of the line under the pointer first.
                func textView(_: NSTextView, menu: NSMenu, for _: NSEvent, at charIndex: Int) -> NSMenu? {
                    guard let line = rendered.line(at: charIndex) else { return menu }
                    menuActions = ConsoleLineAction.actions(for: line)
                    for (index, action) in menuActions.enumerated() {
                        let item = NSMenuItem(title: action.title, action: #selector(performMenuAction(_:)), keyEquivalent: "")
                        item.target = self
                        item.tag = index
                        menu.insertItem(item, at: index)
                    }
                    menu.insertItem(.separator(), at: menuActions.count)
                    return menu
                }

                @objc private func performMenuAction(_ item: NSMenuItem) {
                    guard menuActions.indices.contains(item.tag) else { return }
                    perform(menuActions[item.tag])
                }
            }
        }

    #elseif os(iOS)
        import UIKit

        struct ConsoleTextView: UIViewRepresentable {
            let lines: [LogLine]
            @Binding var isFollowing: Bool
            /// Runs what a line's edit menu offers.
            var perform: (ConsoleLineAction) -> Void = { _ in }

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
                coordinator.perform = perform
                let dynamicTypeSize = context.environment.dynamicTypeSize
                let colorScheme = context.environment.colorScheme
                let fonts = ConsoleFonts(dynamicTypeSize: dynamicTypeSize)

                // The fonts and glyphs are baked into the rendered text, so a new text size or
                // appearance redraws every line.
                let update: ConsoleRenderedLines.Update
                if dynamicTypeSize != coordinator.renderedDynamicTypeSize || colorScheme != coordinator.renderedColorScheme {
                    coordinator.glyphs = ConsoleGlyphs(environment: context.environment)
                    coordinator.renderedDynamicTypeSize = dynamicTypeSize
                    coordinator.renderedColorScheme = colorScheme
                    update = .redraw
                } else {
                    update = coordinator.rendered.update(to: lines)
                }

                switch update {
                case .none:
                    break
                case .redraw:
                    let text = buildAttributedString(from: lines, fonts: fonts, glyphs: coordinator.glyphs, prefixNewline: false, offset: 0)
                    storage.setAttributedString(text.string)
                    coordinator.rendered.redrew(lines, starts: text.starts)
                case let .extend(dropping, appending):
                    storage.beginEditing()
                    if dropping > 0 {
                        storage.deleteCharacters(in: NSRange(location: 0, length: coordinator.rendered.length(ofFirst: dropping)))
                    }
                    let appended = Array(lines[appending...])
                    let text = buildAttributedString(
                        from: appended, fonts: fonts, glyphs: coordinator.glyphs, prefixNewline: true, offset: storage.length
                    )
                    storage.append(text.string)
                    storage.endEditing()
                    coordinator.rendered.extended(dropping: dropping, appended: appended, appendedStarts: text.starts)
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

            /// `lines` as text, a newline between each and, with `prefixNewline`, one before the
            /// first, with where each line starts once the text is placed at `offset`.
            private func buildAttributedString(
                from lines: [LogLine],
                fonts: ConsoleFonts,
                glyphs: ConsoleGlyphs?,
                prefixNewline: Bool,
                offset: Int
            ) -> ConsoleDrawnText {
                let result = NSMutableAttributedString()
                var starts: [Int] = []
                starts.reserveCapacity(lines.count)
                for (index, line) in lines.enumerated() {
                    if index > 0 || prefixNewline {
                        result.append(NSAttributedString(string: "\n"))
                    }
                    starts.append(offset + result.length)

                    let ts = Self.dateFormatter.string(from: line.timestamp)
                    result.append(NSAttributedString(string: ts + " ", attributes: [
                        .font: fonts.code,
                        .foregroundColor: UIColor.tertiaryLabel
                    ]))

                    if let severity = line.level.severity, let glyph = glyphs?.attachment(for: severity, font: fonts.code) {
                        result.append(glyph)
                        result.append(NSAttributedString(string: " ", attributes: [.font: fonts.code]))
                    }

                    if let origin = line.shownOrigin {
                        result.append(NSAttributedString(string: origin + " ", attributes: [
                            .font: fonts.code,
                            .foregroundColor: UIColor.tertiaryLabel
                        ]))
                    }

                    result.append(NSAttributedString(string: line.text, attributes: [
                        .font: fonts.code,
                        .foregroundColor: line.level == .debug ? UIColor.secondaryLabel : UIColor.label
                    ]))
                }
                return ConsoleDrawnText(string: result, starts: starts)
            }

            final class Coordinator: NSObject, UITextViewDelegate {
                /// The lines the text shows, and where each starts.
                var rendered = ConsoleRenderedLines()
                /// The text size the rendered lines' fonts were made for; nil before the first render.
                var renderedDynamicTypeSize: DynamicTypeSize?
                /// The appearance the glyphs were drawn for; nil before the first render.
                var renderedColorScheme: ColorScheme?
                var glyphs: ConsoleGlyphs?
                var isProgrammaticScroll = false
                var isFollowing: Binding<Bool>
                /// Runs what a line's edit menu offers.
                var perform: (ConsoleLineAction) -> Void = { _ in }
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

                /// The edit menu, with the actions of the line the selection starts in first.
                func textView(_: UITextView, editMenuForTextIn range: NSRange, suggestedActions: [UIMenuElement]) -> UIMenu? {
                    guard let line = rendered.line(at: range.location) else { return nil }
                    let actions = ConsoleLineAction.actions(for: line).map { action in
                        UIAction(title: action.title) { [weak self] _ in self?.perform(action) }
                    }
                    return UIMenu(children: [UIMenu(options: .displayInline, children: actions)] + suggestedActions)
                }
            }
        }

    #endif

    /// Lines drawn as text, with where each starts in it.
    struct ConsoleDrawnText {
        let string: NSAttributedString
        let starts: [Int]
    }
#endif
