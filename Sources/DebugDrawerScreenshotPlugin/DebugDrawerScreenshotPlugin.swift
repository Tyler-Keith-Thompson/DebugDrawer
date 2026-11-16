#if DEBUG
    import DebugDrawer
    import SwiftUI

    #if os(macOS)
    import AppKit
    @preconcurrency import ScreenCaptureKit
    import UniformTypeIdentifiers
    #elseif os(iOS)
    import UIKit
    #endif

    // MARK: - Plugin

    public struct ScreenshotPlugin: DebugDrawerPlugin {
        public var title = "Screenshot"
        public var category = "Interface"
        public var icon = "camera"

        public init() {}

        public var body: some View {
            ScreenshotPluginView()
        }
    }

    struct ScreenshotPluginView: View {
        @State private var lastPath: String?
        @State private var isCapturing = false
        @State private var hideDrawer = true
        #if os(macOS)
        /// A capture the Desktop refused (a sandboxed host), waiting for the user to pick where it goes.
        @State private var refusedCapture: PNGDocument?
        @State private var refusedFilename = ""
        #endif

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Hide drawer for screenshot", isOn: $hideDrawer)
                    .toggleStyle(.switch)
                    .controlSize(.small)

                HStack {
                    #if os(macOS)
                    Button("To Desktop") {
                        capture(to: .desktop)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(isCapturing)

                    Button("To Clipboard") {
                        capture(to: .clipboard)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isCapturing)
                    #elseif os(iOS)
                    Button("Capture") {
                        capture(to: .clipboard)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(isCapturing)
                    #endif
                }

                if isCapturing {
                    HStack(spacing: 4) {
                        ProgressView().controlSize(.small)
                        Text("Capturing...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let path = lastPath {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                        Text(path)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                }
            }
            #if os(macOS)
            .fileExporter(
                isPresented: Binding(get: { refusedCapture != nil }, set: { if !$0 { refusedCapture = nil } }),
                document: refusedCapture,
                contentType: .png,
                defaultFilename: refusedFilename
            ) { result in
                switch result {
                case let .success(url): lastPath = url.path
                case let .failure(error): lastPath = "Error: \(error.localizedDescription)"
                }
            }
            #endif
        }

        private enum Destination { case desktop, clipboard }

        private func capture(to destination: Destination) {
            isCapturing = true
            lastPath = nil

            let doCapture: @MainActor () async -> Void = {
                await performCapture(destination: destination)
            }

            if hideDrawer {
                DebugDrawer.shared.performWhileHidden(doCapture)
            } else {
                Task { await doCapture() }
            }
        }

        #if os(macOS)
        private func performCapture(destination: Destination) async {
            guard let window = NSApp?.keyWindow else {
                isCapturing = false
                return
            }

            do {
                let image = try await captureWindow(window)

                switch destination {
                case .desktop:
                    let (png, filename) = try pngFile(image)
                    guard let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first else {
                        throw ScreenshotError.noDesktop
                    }
                    switch try ScreenshotFile.save(png, as: filename, in: desktop) {
                    case let .saved(url):
                        lastPath = url.path
                        NSSound.beep()
                    case .needsLocation:
                        refusedFilename = filename
                        refusedCapture = PNGDocument(data: png)
                    }

                case .clipboard:
                    copyToClipboard(image)
                    lastPath = "Copied to clipboard"
                }
            } catch {
                lastPath = "Error: \(error.localizedDescription)"
            }

            isCapturing = false
        }

        private func captureWindow(_ window: NSWindow) async throws -> NSImage {
            let windowID = CGWindowID(window.windowNumber)
            let windowFrame = window.frame
            let scale = window.screen?.backingScaleFactor ?? 2

            let content = try await SCShareableContent.current
            guard let scWindow = content.windows.first(where: { $0.windowID == windowID }) else {
                throw ScreenshotError.windowNotFound
            }

            let filter = SCContentFilter(desktopIndependentWindow: scWindow)
            let config = SCStreamConfiguration()
            config.width = Int(windowFrame.width * scale)
            config.height = Int(windowFrame.height * scale)
            config.showsCursor = false

            let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            return NSImage(cgImage: cgImage, size: windowFrame.size)
        }

        /// The capture as PNG data, with a timestamped filename.
        private func pngFile(_ image: NSImage) throws -> (Data, String) {
            guard let tiff = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff),
                  let pngData = bitmap.representation(using: .png, properties: [:])
            else {
                throw ScreenshotError.encodingFailed
            }

            let timestamp = ISO8601DateFormatter().string(from: Date())
                .replacingOccurrences(of: ":", with: "-")
            return (pngData, "MergeWard-Debug-\(timestamp).png")
        }

        private func copyToClipboard(_ image: NSImage) {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.writeObjects([image])
        }
        #elseif os(iOS)
        private func performCapture(destination: Destination) async {
            guard let windowScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
                let window = windowScene.windows.first(where: { $0.isKeyWindow }),
                let rootView = window.rootViewController?.view
            else {
                isCapturing = false
                return
            }

            let renderer = UIGraphicsImageRenderer(bounds: rootView.bounds)
            let image = renderer.image { _ in
                rootView.drawHierarchy(in: rootView.bounds, afterScreenUpdates: true)
            }

            switch destination {
            case .desktop:
                // No desktop on iOS — fall through to clipboard
                UIPasteboard.general.image = image
                lastPath = "Copied to clipboard"
            case .clipboard:
                UIPasteboard.general.image = image
                lastPath = "Copied to clipboard"
            }

            isCapturing = false
        }
        #endif

        enum ScreenshotError: LocalizedError {
            case windowNotFound
            case encodingFailed
            case noDesktop

            var errorDescription: String? {
                switch self {
                case .windowNotFound: "Could not find window for capture"
                case .encodingFailed: "Failed to encode screenshot as PNG"
                case .noDesktop: "Could not locate Desktop directory"
                }
            }
        }
    }

    #if os(macOS)
    /// PNG data as a document, for `.fileExporter`.
    struct PNGDocument: FileDocument {
        static let readableContentTypes: [UTType] = [.png]
        let data: Data

        init(data: Data) { self.data = data }

        init(configuration: ReadConfiguration) throws {
            data = configuration.file.regularFileContents ?? Data()
        }

        func fileWrapper(configuration _: WriteConfiguration) throws -> FileWrapper {
            FileWrapper(regularFileWithContents: data)
        }
    }
    #endif

    // MARK: - Convenience installer

    public extension DebugDrawer {
        func installScreenshot() {
            registerGlobal(ScreenshotPlugin())
        }
    }

#endif
