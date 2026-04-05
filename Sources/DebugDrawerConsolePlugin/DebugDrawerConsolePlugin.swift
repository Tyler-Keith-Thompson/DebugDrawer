#if DEBUG
    import Combine
    import DebugDrawer
    import Foundation
    import OSLogClient
    import SwiftUI

    // MARK: - Log line model

    public struct LogLine: Identifiable {
        public let id = UUID()
        public let timestamp: Date
        public let text: String
        public let source: Source
        public let level: Level

        public enum Source: String, Sendable {
            case stdout, stderr, oslog
        }

        public enum Level: Comparable, Sendable {
            case debug, info, notice, error, fault

            var color: Color {
                switch self {
                case .debug: .secondary
                case .info: .primary
                case .notice: .primary
                case .error: .red
                case .fault: .red
                }
            }

            var label: String? {
                switch self {
                case .error: "ERR"
                case .fault: "FLT"
                case .debug: "DBG"
                default: nil
                }
            }
        }
    }

    // MARK: - OSLogClient driver

    /// Receives os_log entries and pushes them into the shared ConsoleLogStore.
    final class ConsoleLogDriver: LogDriver, @unchecked Sendable {
        convenience init() {
            self.init(id: "com.debugdrawer.console")
        }

        #if os(macOS)
            override func processLog(
                level: LogLevel,
                subsystem: String,
                category: String,
                date: Date,
                message: String,
                components _: [OSLogMessageComponent]
            ) {
                handleLog(level: level, subsystem: subsystem, category: category, date: date, message: message)
            }
        #else
            override func processLog(
                level: LogLevel,
                subsystem: String,
                category: String,
                date: Date,
                message: String
            ) {
                handleLog(level: level, subsystem: subsystem, category: category, date: date, message: message)
            }
        #endif

        private func handleLog(level: LogLevel, subsystem: String, category: String, date: Date, message: String) {
            let mapped: LogLine.Level = switch level {
            case .debug: .debug
            case .info: .info
            case .notice: .notice
            case .error: .error
            case .fault: .fault
            case .undefined: .info
            }

            let prefix = subsystem.isEmpty ? "" : "[\(subsystem)/\(category)] "
            let line = LogLine(
                timestamp: date,
                text: "\(prefix)\(message)",
                source: .oslog,
                level: mapped
            )

            Task { @MainActor in
                ConsoleLogStore.shared.ingest(line)
            }
        }
    }

    // MARK: - Log store

    /// Captures stdout, stderr, and os_log output into a ring buffer.
    @MainActor
    public final class ConsoleLogStore: ObservableObject {
        public static let shared = ConsoleLogStore()

        @Published public private(set) var lines: [LogLine] = []
        @Published public var filterLevel: LogLine.Level = .debug

        /// Maximum number of lines retained in the ring buffer.
        public var capacity = 2000

        public var filteredLines: [LogLine] {
            lines.filter { $0.level >= filterLevel }
        }

        private var installed = false
        private let driver = ConsoleLogDriver()
        /// Original stdout fd, used to write diagnostics without triggering capture loop.
        private var originalStdoutFd: Int32 = -1
        /// Subject that receives individual log lines, throttled before publishing to `lines`.
        private let lineSubject = PassthroughSubject<LogLine, Never>()
        private var cancellable: AnyCancellable?

        private init() {
            cancellable = lineSubject
                .collect(.byTime(DispatchQueue.main, .milliseconds(100)))
                .receive(on: DispatchQueue.main)
                .sink { [weak self] batch in
                    guard let self, !batch.isEmpty else { return }
                    self.lines.append(contentsOf: batch)
                    if self.lines.count > self.capacity {
                        self.lines.removeFirst(self.lines.count - self.capacity)
                    }
                }
        }

        // MARK: - Installation

        /// Redirect stdout/stderr and start polling os_log.
        /// Call once at app startup. Safe to call multiple times (no-ops after first).
        public func install() {
            guard !installed else { return }
            installed = true

            // Only redirect stdout/stderr on macOS.
            // On iOS, dup2 on stdout breaks Xcode's debugger attachment.
            #if os(macOS)
                originalStdoutFd = dup(STDOUT_FILENO)
                redirectStream(source: .stdout, fd: STDOUT_FILENO)
                redirectStream(source: .stderr, fd: STDERR_FILENO)
            #endif

            Task {
                do {
                    let store = try OSLogStore(scope: .currentProcessIdentifier)
                    try await OSLogClient.initialize(pollingInterval: .custom(2), logStore: store)
                    await OSLogClient.registerDriver(driver)
                    await OSLogClient.startPolling()
                } catch {
                    logDirect("[DebugDrawer] OSLogClient init failed: \(error)\n")
                }
            }
        }

        /// Write directly to the original stdout fd, bypassing the pipe capture.
        private func logDirect(_ msg: String) {
            guard originalStdoutFd >= 0 else { return }
            msg.withCString { ptr in
                _ = write(originalStdoutFd, ptr, strlen(ptr))
            }
        }

        /// Push a line into the throttled pipeline.
        func ingest(_ line: LogLine) {
            lineSubject.send(line)
        }

        private func redirectStream(source: LogLine.Source, fd: Int32) {
            let pipe = Pipe()
            let originalFd = dup(fd)
            dup2(pipe.fileHandleForWriting.fileDescriptor, fd)

            pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                // Forward to original destination.
                if originalFd >= 0 {
                    data.withUnsafeBytes { buf in
                        if let ptr = buf.baseAddress {
                            _ = write(originalFd, ptr, data.count)
                        }
                    }
                }
                guard let text = String(data: data, encoding: .utf8) else { return }
                let logLines = text.components(separatedBy: "\n")
                    .filter { !$0.isEmpty }
                    .map { LogLine(timestamp: Date(), text: $0, source: source, level: source == .stderr ? .error : .info) }

                Task { @MainActor [weak self] in
                    guard let self else { return }
                    for line in logLines {
                        self.ingest(line)
                    }
                }
            }
        }

        public func clear() {
            lines.removeAll()
        }
    }

    // MARK: - Plugin

    public struct ConsolePlugin: DebugDrawerPlugin {
        public var title = "Console"
        public var icon = "terminal"

        public init() {}

        public var body: some View {
            ConsolePluginView()
        }
    }

    // MARK: - Console view (proper SwiftUI View so @ObservedObject works)

    struct ConsolePluginView: View {
        @ObservedObject private var store = ConsoleLogStore.shared
        @State private var isFollowing = true
        @State private var searchText = ""

        private var visibleLines: [LogLine] {
            let filtered = store.filteredLines
            guard !searchText.isEmpty else { return filtered }
            let q = searchText.lowercased()
            return filtered.filter { $0.text.lowercased().contains(q) }
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                // Search field
                TextField("Search logs...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)

                // Toolbar — filter picker is in its own view to avoid
                // re-creating the NSSegmentedControl on every log batch.
                ConsoleToolbarView(
                    lineCount: visibleLines.count,
                    isFollowing: $isFollowing,
                    visibleLines: visibleLines
                )

                ConsoleTextView(
                    lines: visibleLines,
                    isFollowing: $isFollowing
                )
                .frame(minHeight: 120, maxHeight: 300)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
    }

    /// Extracted toolbar so the segmented picker doesn't get rebuilt on every log update.
    /// Only `lineCount` and `isFollowing` change frequently — the picker binding
    /// (`filterLevel`) is stable and won't cause the NSSegmentedControl to be recreated.
    struct ConsoleToolbarView: View {
        let lineCount: Int
        @Binding var isFollowing: Bool
        let visibleLines: [LogLine]
        @ObservedObject private var store = ConsoleLogStore.shared

        private static let copyDateFormatter: DateFormatter = {
            let f = DateFormatter()
            f.dateFormat = "HH:mm:ss.SSS"
            return f
        }()

        var body: some View {
            HStack(spacing: 8) {
                Text("\(lineCount) lines")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !isFollowing {
                    Button("Resume") { isFollowing = true }
                        .font(.caption)
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                }

                Spacer()

                ConsoleFilterPicker(filterLevel: $store.filterLevel)

                Button("Copy All") {
                    let text = visibleLines.map { line in
                        let ts = Self.copyDateFormatter.string(from: line.timestamp)
                        let badge = line.level.label.map { $0 + " " } ?? ""
                        return "\(ts) \(badge)\(line.text)"
                    }.joined(separator: "\n")
                    debugDrawerCopyToClipboard(text)
                }
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Button("Clear") { store.clear() }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// The segmented picker in its own view to prevent SwiftUI from
    /// recreating the NSSegmentedControl when the parent re-renders.
    struct ConsoleFilterPicker: View {
        @Binding var filterLevel: LogLine.Level

        var body: some View {
            Picker(selection: $filterLevel) {
                Text("All").tag(LogLine.Level.debug)
                Text("Info+").tag(LogLine.Level.info)
                Text("Errors").tag(LogLine.Level.error)
            } label: {
                EmptyView()
            }
            .pickerStyle(.segmented)
            .frame(width: 160)
            .controlSize(.mini)
        }
    }

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

                let textView = scrollView.documentView as! NSTextView
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
                let f = DateFormatter()
                f.dateFormat = "HH:mm:ss.SSS"
                return f
            }()

            private func buildAttributedString(from lines: [LogLine], prefixNewline: Bool) -> NSAttributedString {
                let result = NSMutableAttributedString()
                for (i, line) in lines.enumerated() {
                    if i > 0 || prefixNewline {
                        result.append(NSAttributedString(string: "\n"))
                    }

                    let ts = Self.dateFormatter.string(from: line.timestamp)
                    result.append(NSAttributedString(string: ts + " ", attributes: [
                        .font: Self.smallMonoFont,
                        .foregroundColor: Self.timestampColor,
                    ]))

                    if let badge = line.level.label {
                        result.append(NSAttributedString(string: badge + " ", attributes: [
                            .font: Self.badgeFont,
                            .foregroundColor: nsColor(for: line.level),
                        ]))
                    }

                    if line.source == .oslog {
                        result.append(NSAttributedString(string: "⌘ ", attributes: [
                            .font: Self.smallMonoFont,
                            .foregroundColor: Self.timestampColor,
                        ]))
                    }

                    result.append(NSAttributedString(string: line.text, attributes: [
                        .font: Self.monoFont,
                        .foregroundColor: nsColor(for: line.level),
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

                @objc func scrollViewDidScroll(_: Notification) {
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
                textView.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
                textView.delegate = context.coordinator
                context.coordinator.textView = textView
                return textView
            }

            func updateUIView(_ textView: UITextView, context: Context) {
                guard let storage = textView.textStorage as? NSTextStorage else { return }

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
                    storage.setAttributedString(buildAttributedString(from: lines, prefixNewline: false))
                    context.coordinator.renderedLineCount = newCount
                }

                if isFollowing, storage.length > 0 {
                    context.coordinator.isProgrammaticScroll = true
                    let range = NSRange(location: storage.length - 1, length: 1)
                    textView.scrollRangeToVisible(range)
                    context.coordinator.isProgrammaticScroll = false
                }
            }

            private static let monoFont = UIFont.monospacedSystemFont(ofSize: 10, weight: .regular)
            private static let smallMonoFont = UIFont.monospacedSystemFont(ofSize: 9, weight: .regular)
            private static let badgeFont = UIFont.monospacedSystemFont(ofSize: 8, weight: .bold)
            private static let timestampColor = UIColor.tertiaryLabel
            private static let dateFormatter: DateFormatter = {
                let f = DateFormatter()
                f.dateFormat = "HH:mm:ss.SSS"
                return f
            }()

            private func buildAttributedString(from lines: [LogLine], prefixNewline: Bool) -> NSAttributedString {
                let result = NSMutableAttributedString()
                for (i, line) in lines.enumerated() {
                    if i > 0 || prefixNewline {
                        result.append(NSAttributedString(string: "\n"))
                    }

                    let ts = Self.dateFormatter.string(from: line.timestamp)
                    result.append(NSAttributedString(string: ts + " ", attributes: [
                        .font: Self.smallMonoFont,
                        .foregroundColor: Self.timestampColor,
                    ]))

                    if let badge = line.level.label {
                        result.append(NSAttributedString(string: badge + " ", attributes: [
                            .font: Self.badgeFont,
                            .foregroundColor: uiColor(for: line.level),
                        ]))
                    }

                    if line.source == .oslog {
                        result.append(NSAttributedString(string: "⌘ ", attributes: [
                            .font: Self.smallMonoFont,
                            .foregroundColor: Self.timestampColor,
                        ]))
                    }

                    result.append(NSAttributedString(string: line.text, attributes: [
                        .font: Self.monoFont,
                        .foregroundColor: uiColor(for: line.level),
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

    // MARK: - Convenience installer

    public extension DebugDrawer {
        /// Install the console capture plugin. Call once at app startup.
        /// Captures stdout, stderr, and os_log entries.
        func installConsole() {
            ConsoleLogStore.shared.install()
            registerGlobal(ConsolePlugin())
        }
    }
#endif
