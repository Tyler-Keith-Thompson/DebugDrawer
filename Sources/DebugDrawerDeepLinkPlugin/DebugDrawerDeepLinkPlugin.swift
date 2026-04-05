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
        public var icon = "link"

        public init() {}

        public var body: some View {
            DeepLinkPluginView()
        }
    }

    // MARK: - View

    private struct DeepLinkPluginView: View {
        private static let historyKey = "com.debugdrawer.deeplink.history"
        private static let maxHistory = 30

        private static let presets: [(String, String)] = [
            ("HTTPS", "https://example.com/path"),
            ("Custom Scheme", "myapp://deeplink/screen"),
            ("Settings (iOS)", "App-prefs:root=General"),
            ("Mail", "mailto:test@example.com"),
            ("Tel", "tel:+1234567890"),
        ]

        @State private var urlText = ""
        @State private var history: [String] = {
            UserDefaults.standard.stringArray(forKey: DeepLinkPluginView.historyKey) ?? []
        }()
        @State private var lastResult: String?

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                // Input
                HStack(spacing: 4) {
                    TextField("Enter URL...", text: $urlText)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 10, design: .monospaced))
                        #if os(iOS)
                            .keyboardType(.URL)
                            .autocapitalization(.none)
                        #endif

                    Button("Open") { openURL() }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .disabled(urlText.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                if let result = lastResult {
                    Text(result)
                        .font(.system(size: 9))
                        .foregroundStyle(result.hasPrefix("Error") ? .red : .green)
                }

                // Presets
                Divider()
                Text("Presets")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(Self.presets, id: \.1) { label, url in
                    Button {
                        urlText = url
                    } label: {
                        HStack {
                            Text(label)
                                .font(.system(size: 10))
                            Spacer()
                            Text(url)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
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
                        Button("Clear") {
                            history.removeAll()
                            saveHistory()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }

                    ForEach(history, id: \.self) { entry in
                        Button {
                            urlText = entry
                        } label: {
                            Text(entry)
                                .font(.system(size: 9, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }

        private func openURL() {
            let trimmed = urlText.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return }
            guard let url = URL(string: trimmed) else {
                lastResult = "Error: Invalid URL"
                return
            }

            addToHistory(trimmed)

            #if os(macOS)
                NSWorkspace.shared.open(url)
                lastResult = "Opened: \(trimmed)"
            #elseif os(iOS)
                UIApplication.shared.open(url) { success in
                    Task { @MainActor in
                        lastResult = success ? "Opened: \(trimmed)" : "Error: Could not open URL"
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

    // MARK: - Convenience installer

    public extension DebugDrawer {
        func installDeepLink() {
            registerGlobal(DeepLinkPlugin())
        }
    }
#endif
