#if DEBUG
    import DebugDrawer
    import SwiftUI
    import UniformTypeIdentifiers
    #if os(iOS)
        // Mac Catalyst takes this branch too: PhotosPicker and the Files importer work in a Mac
        // window as they do on iPad, and neither asks for a permission.
        import PhotosUI
    #endif

    /// The plugin's body: the mockup and where it comes from, how it is drawn (Show, opacity,
    /// blend and scale) and where (the offset and Move), with Clear. It keeps whether the file
    /// importer is open and, on iOS, the photo being picked.
    struct DesignOverlayView: View {
        let mockup: Mockup?
        let failure: MockupFailure?
        /// The window's width in points, for the mockup's size; `nil` before it is laid out.
        let windowWidth: CGFloat?
        @Binding var settings: DesignOverlaySettings
        @Binding var isMoving: Bool
        let sources: MockupSources
        let clear: () -> Void
        @State var isImporting = false
        #if os(iOS)
            @State private var photo: PhotosPickerItem?
        #endif
        let inspection = Inspection<Self>()

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                MockupSummaryRow(mockup: mockup, scale: settings.scale, windowWidth: windowWidth)
                if let failure {
                    DebugDrawerIssueRow(failure == .notSaved ? "Not saved" : "Not shown", severity: failure == .notSaved ? .warning : .error) {
                        Text(failure.message)
                    }
                }
                if mockup != nil {
                    MockupAppearanceSection(settings: $settings)
                    MockupPositionSection(offset: $settings.offset, isMoving: $isMoving, isVisible: settings.isVisible)
                }
                DebugDrawerActionRow {
                    #if os(iOS)
                        PhotosPicker(selection: $photo, matching: .images) {
                            Label("Photos", systemImage: "photo.on.rectangle")
                        }
                        .accessibilityLabel("Pick a mockup from Photos")
                        Button("Files…") { isImporting = true }
                            .accessibilityLabel("Files…, pick a mockup")
                    #else
                        Button("Choose File…") { isImporting = true }
                            .accessibilityLabel("Choose File…, a mockup")
                        Button("Paste", action: sources.paste)
                            .accessibilityLabel("Paste a mockup")
                    #endif
                    if mockup != nil, settings.offset != .zero {
                        Button("Reset Position") { settings.offset = .zero }
                            .accessibilityLabel("Reset Position of the mockup")
                    }
                } trailing: {
                    if mockup != nil {
                        Button("Clear", role: .destructive, action: clear)
                            .debugDrawerButtonStyle(.destructive)
                            .accessibilityLabel("Clear the mockup")
                    }
                }
            }
            .fileImporter(isPresented: $isImporting, allowedContentTypes: [.image]) { result in
                switch result {
                case let .success(url): sources.openFile(url)
                case .failure: sources.fail(.unreadable)
                }
            }
            #if os(iOS)
            .onChange(of: photo) { _, item in
                guard let item else { return }
                photo = nil
                let sources = sources
                Task {
                    do {
                        if let data = try await item.loadTransferable(type: Data.self) {
                            sources.open(data)
                        } else {
                            sources.fail(.notAnImage)
                        }
                    } catch {
                        sources.fail(.unreadable)
                    }
                }
            }
            #endif
            .onReceive(inspection.notice) { inspection.visit(self, $0) }
        }
    }

    /// The mockup's pixel size and the size it is drawn at, beside a thumbnail; before one is
    /// picked, where to pick one.
    struct MockupSummaryRow: View {
        let mockup: Mockup?
        let scale: MockupScale
        let windowWidth: CGFloat?
        @ScaledMetric(relativeTo: .body) private var thumbnailHeight: CGFloat = 44

        var body: some View {
            if let mockup {
                DebugDrawerRow(mockup.pixelSize.pixelsText, systemImage: "square.on.square.dashed") {
                    Text(drawnSize(of: mockup))
                } accessory: {
                    Image(decorative: mockup.image, scale: 1)
                        .resizable()
                        .scaledToFit()
                        .frame(height: thumbnailHeight)
                        .accessibilityHidden(true)
                }
            } else {
                DebugDrawerRow("No mockup", systemImage: "square.on.square.dashed") {
                    Text("Pick a design comp to lay over the app, under the drawer. It is kept in Caches until Clear.")
                } accessory: {
                    EmptyView()
                }
            }
        }

        /// "Drawn at @3x: 430 × 932 pt".
        private func drawnSize(of mockup: Mockup) -> String {
            guard let windowWidth else { return "Drawn at \(scale.title)" }
            let size = scale.size(ofMockup: mockup.pixelSize, windowWidth: windowWidth)
            let factor = scale.factor(forMockupWidth: mockup.pixelSize.width, windowWidth: windowWidth)
            let how = switch (scale, factor) {
            case let (.automatic, factor?): "Drawn at @\(factor)x (automatic)"
            case (.fitWidth, _), (_, nil): "Drawn to fit the width"
            case let (_, factor?): "Drawn at @\(factor)x"
            }
            return "\(how): \(Int(size.width.rounded())) × \(Int(size.height.rounded())) pt"
        }
    }

    extension CGSize {
        /// A size in pixels, "1290 × 2796 px".
        fileprivate var pixelsText: String {
            "\(Int(width)) × \(Int(height)) px"
        }
    }
#endif
