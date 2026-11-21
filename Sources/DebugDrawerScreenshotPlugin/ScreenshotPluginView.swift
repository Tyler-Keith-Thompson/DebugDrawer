#if DEBUG
    #if os(macOS)
        import AppKit
        import UniformTypeIdentifiers
    #elseif os(iOS)
        import UIKit
    #endif
    import DebugDrawer
    import SwiftUI

    /// The plugin's body: whether a capture hides the drawer, where the last capture went, the
    /// capture itself, small, and the capture buttons.
    ///
    /// It draws ``ScreenshotModel``'s snapshots from its transport and sends it what the user does.
    /// Writing the clipboard, and on the Mac the save panel a refused save falls back to, stay here.
    struct ScreenshotPluginView: View {
        @StateObject private var transport: DebugDrawerPluginTransport<ScreenshotSnapshot, ScreenshotCommand>
        let inspection = Inspection<Self>() // from/for ViewInspector.

        /// - Parameter transport: Joins the view to the model; made once, for the view's lifetime.
        init(transport: @escaping @autoclosure () -> DebugDrawerPluginTransport<ScreenshotSnapshot, ScreenshotCommand>) {
            _transport = StateObject(wrappedValue: transport())
        }

        var body: some View {
            let snapshot = transport.snapshot
            let isCapturing = snapshot.status == .capturing
            VStack(alignment: .leading, spacing: 0) {
                DebugDrawerRow("Hide drawer for screenshot", isOn: hidesDrawer)

                switch snapshot.status {
                case let .saved(path):
                    DebugDrawerIssueRow("Saved", severity: .ok, subline: path)
                case .copied:
                    DebugDrawerIssueRow("Saved", severity: .ok, subline: "Copied to clipboard")
                case let .failed(failure):
                    DebugDrawerIssueRow("Error: \(failure.message)", severity: .error)
                case .ready, .capturing, .needsLocation, .copying:
                    EmptyView()
                }

                if let capture = snapshot.capture, let image = capture.image.platformImage {
                    DebugDrawerCodeBlock {
                        Image(platformImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 120)
                            .accessibilityLabel("Last capture")
                    }
                }

                DebugDrawerActionRow {
                    #if os(macOS)
                        Button("To Desktop") {
                            transport.send(ScreenshotCommand(.capture))
                            transport.send(ScreenshotCommand(.save))
                        }
                        .debugDrawerButtonStyle(.primary)
                        .disabled(isCapturing)

                        Button("To Clipboard") {
                            transport.send(ScreenshotCommand(.capture))
                            transport.send(ScreenshotCommand(.copy))
                        }
                        .disabled(isCapturing)
                    #elseif os(iOS)
                        // iOS has no Desktop; every capture goes to the clipboard.
                        Button("Capture") {
                            transport.send(ScreenshotCommand(.capture))
                            transport.send(ScreenshotCommand(.copy))
                        }
                        .debugDrawerButtonStyle(.primary)
                        .disabled(isCapturing)
                    #endif

                    if snapshot.capture != nil, !isCapturing {
                        Button("Clear") {
                            transport.send(ScreenshotCommand(.clear))
                        }
                    }

                    if isCapturing {
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
            // The drawer may have hidden this view while capturing, so a copy asked for then is
            // made once it shows again.
            .onAppear(perform: copyIfAsked)
            .onChange(of: snapshot.status) { copyIfAsked() }
            .onReceive(inspection.notice) { inspection.visit(self, $0) }
            #if os(macOS)
                .fileExporter(
                    isPresented: needsLocation,
                    document: needsLocationDocument,
                    contentType: .png,
                    defaultFilename: needsLocationFilename
                ) { result in
                    switch result {
                    case let .success(url): transport.send(ScreenshotCommand(.exported(path: url.path)))
                    case let .failure(error): transport.send(ScreenshotCommand(.exportFailed(error.localizedDescription)))
                    }
                }
            #endif
        }

        /// Whether a capture hides the drawer, read from the snapshot and changed through the model.
        private var hidesDrawer: Binding<Bool> {
            Binding(
                get: { transport.snapshot.hidesDrawer },
                set: { transport.send(ScreenshotCommand(.setHidesDrawer($0))) }
            )
        }

        /// Puts the last capture on the clipboard when the model asks, and tells it so.
        private func copyIfAsked() {
            guard transport.snapshot.status == .copying, let capture = transport.snapshot.capture else { return }
            #if os(macOS)
                guard let image = capture.image.platformImage else { return }
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.writeObjects([image])
            #elseif os(iOS)
                UIPasteboard.general.image = capture.image.platformImage
            #endif
            transport.send(ScreenshotCommand(.copied))
        }

        #if os(macOS)
            /// Whether the save panel is open: while the Desktop refused the last capture.
            private var needsLocation: Binding<Bool> {
                Binding(
                    get: { needsLocationFilename != nil },
                    set: { if !$0 { transport.send(ScreenshotCommand(.cancelExport)) } }
                )
            }

            /// The name the Desktop refused, which the save panel suggests.
            private var needsLocationFilename: String? {
                guard case let .needsLocation(filename) = transport.snapshot.status else { return nil }
                return filename
            }

            /// The capture the Desktop refused, for the save panel to write.
            private var needsLocationDocument: PNGDocument? {
                guard needsLocationFilename != nil, let capture = transport.snapshot.capture else { return nil }
                return PNGDocument(data: capture.image.png)
            }
        #endif
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

    extension ScreenshotFailure {
        /// What the view says went wrong.
        fileprivate var message: String {
            switch self {
            case .noWindow: "No key window to capture"
            case .encodingFailed: "Failed to encode screenshot as PNG"
            case .noDesktop: "Could not locate Desktop directory"
            case let .writeFailed(reason), let .exportFailed(reason): reason
            }
        }
    }

    extension ScreenshotImage {
        /// The PNG decoded, at the window's scale, or `nil` when it doesn't decode.
        fileprivate var platformImage: PlatformImage? {
            #if os(macOS)
                guard let bitmap = NSBitmapImageRep(data: png) else { return nil }
                // Sized in points, so it draws and pastes at the window's scale.
                bitmap.size = NSSize(width: Double(pixelWidth) / scale, height: Double(pixelHeight) / scale)
                let image = NSImage(size: bitmap.size)
                image.addRepresentation(bitmap)
                return image
            #else
                return UIImage(data: png, scale: scale)
            #endif
        }
    }

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
