#if DEBUG
    #if os(macOS)
        import AppKit
    #elseif os(iOS)
        import UIKit
    #endif
    import DebugDrawer
    import SwiftUI

    // MARK: - Plugin

    public struct DeepLinkPlugin: DebugDrawerPlugin {
        public var title = "Deep Link Tester"
        public var category = "App"
        public var icon = "link"

        public init() {}

        public var body: some View {
            DeepLinkPluginView()
        }
    }

    // MARK: - View

    /// Keeps the typed URL, the result and the history (in `UserDefaults`); `DeepLinkForm` draws them.
    private struct DeepLinkPluginView: View {
        private static let historyKey = "com.debugdrawer.deeplink.history"
        private static let maxHistory = 30

        private static let presets: [DeepLinkForm.Preset] = [
            .init(label: "HTTPS", url: "https://example.com/path"),
            .init(label: "Custom Scheme", url: "myapp://deeplink/screen"),
            .init(label: "Settings (iOS)", url: "App-prefs:root=General"),
            .init(label: "Mail", url: "mailto:test@example.com"),
            .init(label: "Tel", url: "tel:+1234567890")
        ]

        @State private var urlText = ""
        @State private var history: [String] = {
            UserDefaults.standard.stringArray(forKey: DeepLinkPluginView.historyKey) ?? []
        }()
        @State private var lastResult: String?

        var body: some View {
            DeepLinkForm(
                urlText: $urlText,
                lastResult: lastResult,
                presets: Self.presets,
                history: history,
                onOpen: open
            ) {
                history.removeAll()
                saveHistory()
            }
        }

        private func open(_ url: URL) {
            let opened = url.absoluteString
            addToHistory(opened)

            #if os(macOS)
                NSWorkspace.shared.open(url)
                lastResult = "Opened: \(opened)"
            #elseif os(iOS)
                UIApplication.shared.open(url) { success in
                    Task { @MainActor in
                        lastResult = success ? "Opened: \(opened)" : "Error: Could not open URL"
                    }
                }
            #endif
        }

        private func addToHistory(_ url: String) {
            history.removeAll { $0 == url }
            history.insert(url, at: 0)
            if history.count > Self.maxHistory {
                history = Array(history.prefix(Self.maxHistory))
            }
            saveHistory()
        }

        private func saveHistory() {
            UserDefaults.standard.set(history, forKey: Self.historyKey)
        }
    }

    /// The URL field with its Open link, the result of the last open, the presets and the history.
    struct DeepLinkForm: View {
        /// A named example URL.
        struct Preset: Equatable {
            var label: String
            var url: String
        }

        @Binding var urlText: String
        /// "Opened: …" or "Error: …" after an open, nil before one.
        let lastResult: String?
        let presets: [Preset]
        /// URLs opened before, most recent first.
        let history: [String]
        let onOpen: (URL) -> Void
        let onClear: () -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                // Input
                HStack(spacing: 4) {
                    TextField("Enter URL...", text: $urlText)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.caption2, design: .monospaced))
                        .textContentType(.URL)
                        .accessibilityLabel("URL to open")
                        #if os(iOS)
                            .keyboardType(.URL)
                            .autocapitalization(.none)
                        #endif

                    Group {
                        if let url = typedURL {
                            Link("Open", destination: url)
                                .environment(\.openURL, OpenURLAction { url in
                                    onOpen(url)
                                    return .handled
                                })
                        } else {
                            Button("Open") {}
                                .disabled(true)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }

                if let result = lastResult {
                    Text(result)
                        .font(.caption2)
                        .foregroundStyle(result.hasPrefix("Error") ? .red : .green)
                }

                // Presets
                Divider()
                Text("Presets")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(presets, id: \.url) { preset in
                    Button {
                        urlText = preset.url
                    } label: {
                        HStack {
                            Text(preset.label)
                                .font(.caption2)
                            Spacer()
                            Text(preset.url)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                                .truncationMode(.middle)
                        }
                    }
                    .buttonStyle(.plain)
                }

                // History
                if !history.isEmpty {
                    Divider()
                    HStack {
                        Text("History (\(history.count))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Clear", action: onClear)
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }

                    ForEach(history, id: \.self) { entry in
                        Button {
                            urlText = entry
                        } label: {
                            Text(entry)
                                .font(.system(.caption2, design: .monospaced))
                                .lineLimit(3)
                                .truncationMode(.middle)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }

        /// The URL typed in the field, or nil while it's empty or not a URL.
        private var typedURL: URL? {
            let trimmed = urlText.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty ? nil : URL(string: trimmed)
        }
    }

    // MARK: - Convenience installer

    public extension DebugDrawer {
        func installDeepLink() {
            registerGlobal(DeepLinkPlugin())
        }
    }
#endif
