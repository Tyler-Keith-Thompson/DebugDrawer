import DebugDrawer
import SwiftUI

// MARK: - Plugin

// The public API compiles in every configuration; the implementation under `#if DEBUG` below does
// not, so release builds get an empty view and an installer that registers nothing.

/// Captures the app's key window: on macOS to a PNG on the Desktop or to the clipboard, on iOS to
/// the clipboard.
public struct ScreenshotPlugin: DebugDrawerPlugin {
    /// The plugin's identity in the drawer, which its saved state, HUD pin and badges are kept under.
    public var id: String {
        "ScreenshotPlugin"
    }

    public var title = "Screenshot"
    public var category = "Interface"
    public var icon = "camera"

    #if DEBUG
        /// The store the plugin shows and captures into, or `nil` for ``ScreenshotStore/shared``,
        /// which is made only once something reads it.
        private let store: ScreenshotStore?

        public init() {
            store = nil
        }

        /// - Parameter store: The store to show and capture into in place of the shared one.
        init(store: ScreenshotStore) {
            self.store = store
        }
    #else
        public init() {}
    #endif

    public var body: some View {
        #if DEBUG
            ScreenshotPluginView(store: store ?? .shared)
        #else
            EmptyView()
        #endif
    }

    /// Counts `drawer` as one that holds the plugin.
    @MainActor public func install(in drawer: DebugDrawer) {
        #if DEBUG
            (store ?? .shared).install(in: ObjectIdentifier(drawer))
        #endif
    }

    /// Once the last drawer that held the plugin removes it, drops the last capture, where it
    /// went, and a capture still waiting for a place to be saved. Files already saved stay.
    @MainActor public func uninstall(from drawer: DebugDrawer) {
        #if DEBUG
            (store ?? .shared).uninstall(from: ObjectIdentifier(drawer))
        #endif
    }
}

// MARK: - Convenience installer

public extension DebugDrawer {
    /// Registers the Screenshot plugin.
    func installScreenshot() {
        #if DEBUG
            registerGlobal(ScreenshotPlugin())
        #endif
    }
}

#if DEBUG
    #if os(macOS)
    import AppKit
    import UniformTypeIdentifiers
    #elseif os(iOS)
    import UIKit
    #endif

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

        /// The drawers the plugin is installed in; the last to remove it drops the capture.
        private var installations: Set<ObjectIdentifier> = []

        /// Counts `drawer` as one the plugin is installed in.
        func install(in drawer: ObjectIdentifier) {
            installations.insert(drawer)
        }

        /// Uncounts `drawer`; once no drawer holds the plugin, drops the last capture and its
        /// result, and on the Mac a capture waiting for a place to be saved. Whether to hide the
        /// drawer stays, and a capture under way finishes.
        func uninstall(from drawer: ObjectIdentifier) {
            guard installations.remove(drawer) != nil, installations.isEmpty else { return }
            lastPath = nil
            lastCapture = nil
            #if os(macOS)
            refusedCapture = nil
            refusedFilename = ""
            #endif
        }
    }

    struct ScreenshotPluginView: View {
        @ObservedObject var store = ScreenshotStore.shared

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                DebugDrawerRow("Hide drawer for screenshot", isOn: $store.hideDrawer)

                if let path = store.lastPath {
                    if path.hasPrefix("Error") {
                        DebugDrawerIssueRow(path, severity: .error)
                    } else {
                        DebugDrawerIssueRow("Saved", severity: .ok, subline: path)
                    }
                }

                if let lastCapture = store.lastCapture {
                    DebugDrawerCodeBlock {
                        Image(platformImage: lastCapture)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 120)
                            .accessibilityLabel("Last capture")
                    }
                }

                DebugDrawerActionRow {
                    #if os(macOS)
                    Button("To Desktop") {
                        capture(to: .desktop)
                    }
                    .debugDrawerButtonStyle(.primary)
                    .disabled(store.isCapturing)

                    Button("To Clipboard") {
                        capture(to: .clipboard)
                    }
                    .disabled(store.isCapturing)
                    #elseif os(iOS)
                    Button("Capture") {
                        capture(to: .clipboard)
                    }
                    .debugDrawerButtonStyle(.primary)
                    .disabled(store.isCapturing)
                    #endif

                    if store.isCapturing {
                        HStack(spacing: 4) {
                            ProgressView().controlSize(.small)
                            Text("Capturing…")
                                .debugDrawerFont(.secondary)
                                .debugDrawerForegroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
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
                // The app's key window, not the drawer's panel when its search field has focus.
                guard let window = debugDrawerAppKeyWindow else { throw ScreenshotError.noWindow }
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
            // The app's key window, not the drawer's when its search field has focus.
            guard let window = debugDrawerAppKeyWindow else {
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

#endif
