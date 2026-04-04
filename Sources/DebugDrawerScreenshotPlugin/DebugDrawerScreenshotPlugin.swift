#if DEBUG
    import AppKit
    import DebugDrawer
    @preconcurrency import ScreenCaptureKit
    import SwiftUI

    #if os(macOS)

    // MARK: - Plugin

    public struct ScreenshotPlugin: DebugDrawerPlugin {
        public var title = "Screenshot"
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

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Hide drawer for screenshot", isOn: $hideDrawer)
                    .toggleStyle(.switch)
                    .controlSize(.small)

                HStack {
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

        private func performCapture(destination: Destination) async {
            guard let window = NSApp?.keyWindow else {
                isCapturing = false
                return
            }

            do {
                let image = try await captureWindow(window)

                switch destination {
                case .desktop:
                    let path = try saveToDesktop(image)
                    lastPath = path
                    NSSound.beep()

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

        private func saveToDesktop(_ image: NSImage) throws -> String {
            guard let tiff = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff),
                  let pngData = bitmap.representation(using: .png, properties: [:])
            else {
                throw ScreenshotError.encodingFailed
            }

            let timestamp = ISO8601DateFormatter().string(from: Date())
                .replacingOccurrences(of: ":", with: "-")
            let filename = "MergeWard-Debug-\(timestamp).png"

            guard let desktopURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first else {
                throw ScreenshotError.noDesktop
            }

            let fileURL = desktopURL.appendingPathComponent(filename)
            try pngData.write(to: fileURL)
            return fileURL.path
        }

        private func copyToClipboard(_ image: NSImage) {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.writeObjects([image])
        }

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

    // MARK: - Convenience installer

    public extension DebugDrawer {
        func installScreenshot() {
            registerGlobal(ScreenshotPlugin())
        }
    }

    #endif // os(macOS)
#endif
