#if DEBUG
    import DebugDrawer
    import SwiftUI

    #if os(macOS)
    import AppKit
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

    /// What the plugin shows between captures. It outlives the plugin's view, which the drawer
    /// removes while it hides for a capture, so a result reported then is still there after.
    @MainActor
    final class ScreenshotStore: ObservableObject {
        static let shared = ScreenshotStore()

        @Published var lastPath: String?
        @Published var isCapturing = false
        /// The last capture, shown small so the developer sees what was taken.
        @Published var lastCapture: PlatformImage?
        @Published var hideDrawer = true
        #if os(macOS)
        /// A capture the Desktop refused (a sandboxed host), waiting for the user to pick where it goes.
        @Published var refusedCapture: PNGDocument?
        @Published var refusedFilename = ""
        #endif

        private init() {}
    }

    struct ScreenshotPluginView: View {
        @ObservedObject private var store = ScreenshotStore.shared

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Hide drawer for screenshot", isOn: $store.hideDrawer)
                    .toggleStyle(.switch)
                    .controlSize(.small)

                HStack {
                    #if os(macOS)
                    Button("To Desktop") {
                        capture(to: .desktop)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(store.isCapturing)

                    Button("To Clipboard") {
                        capture(to: .clipboard)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(store.isCapturing)
                    #elseif os(iOS)
                    Button("Capture") {
                        capture(to: .clipboard)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(store.isCapturing)
                    #endif
                }

                if store.isCapturing {
                    HStack(spacing: 4) {
                        ProgressView().controlSize(.small)
                        Text("Capturing...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let path = store.lastPath {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                            .accessibilityHidden(true)
                        Text(path)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .truncationMode(.head)
                    }
                    .accessibilityElement(children: .combine)
                }

                if let lastCapture = store.lastCapture {
                    Image(platformImage: lastCapture)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(.separator))
                        .accessibilityLabel("Last capture")
                }
            }
            #if os(macOS)
            .fileExporter(
                isPresented: Binding(get: { store.refusedCapture != nil }, set: { if !$0 { store.refusedCapture = nil } }),
                document: store.refusedCapture,
                contentType: .png,
                defaultFilename: store.refusedFilename
            ) { result in
                switch result {
                case let .success(url): store.lastPath = url.path
                case let .failure(error): store.lastPath = "Error: \(error.localizedDescription)"
                }
            }
            #endif
        }

        private enum Destination { case desktop, clipboard }

        private func capture(to destination: Destination) {
            store.isCapturing = true
            store.lastPath = nil
            store.lastCapture = nil

            let doCapture: @MainActor () async -> Void = {
                await performCapture(destination: destination)
            }

            // The HUD is always left out of the capture; the drawer only when asked.
            DebugDrawer.shared.performWhileHidden(drawer: store.hideDrawer, doCapture)
        }

        #if os(macOS)
        private func performCapture(destination: Destination) async {
            do {
                guard let window = NSApp?.keyWindow else { throw ScreenshotError.noWindow }
                guard let bitmap = WindowCapture.bitmap(of: window),
                      let png = bitmap.representation(using: .png, properties: [:])
                else { throw ScreenshotError.encodingFailed }
                let image = NSImage(size: bitmap.size)
                image.addRepresentation(bitmap)
                store.lastCapture = image

                switch destination {
                case .desktop:
                    let filename = ScreenshotFile.filename(appName: ScreenshotFile.appName, at: Date())
                    guard let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first else {
                        throw ScreenshotError.noDesktop
                    }
                    switch try ScreenshotFile.save(png, as: filename, in: desktop) {
                    case let .saved(url):
                        store.lastPath = url.path
                    case .needsLocation:
                        store.refusedFilename = filename
                        store.refusedCapture = PNGDocument(data: png)
                    }

                case .clipboard:
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.writeObjects([image])
                    store.lastPath = "Copied to clipboard"
                }
            } catch {
                store.lastPath = "Error: \(error.localizedDescription)"
            }

            store.isCapturing = false
        }
        #elseif os(iOS)
        private func performCapture(destination _: Destination) async {
            guard let window = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive })?
                .windows.first(where: \.isKeyWindow)
            else {
                store.lastPath = "Error: \(ScreenshotError.noWindow.localizedDescription)"
                store.isCapturing = false
                return
            }

            // iOS has no Desktop; every capture goes to the clipboard.
            let image = WindowCapture.image(of: window)
            UIPasteboard.general.image = image
            store.lastCapture = image
            store.lastPath = "Copied to clipboard"
            store.isCapturing = false
        }
        #endif

        enum ScreenshotError: LocalizedError {
            case noWindow
            case encodingFailed
            case noDesktop

            var errorDescription: String? {
                switch self {
                case .noWindow: "No key window to capture"
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

    extension Image {
        /// A SwiftUI image of an AppKit or UIKit image.
        fileprivate init(platformImage: PlatformImage) {
            #if os(macOS)
            self.init(nsImage: platformImage)
            #else
            self.init(uiImage: platformImage)
            #endif
        }
    }

    // MARK: - Convenience installer

    public extension DebugDrawer {
        func installScreenshot() {
            registerGlobal(ScreenshotPlugin())
        }
    }

#endif
