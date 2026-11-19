#if DEBUG
    import Combine
    import Foundation
    #if os(macOS)
        import AppKit
        import UniformTypeIdentifiers
    #endif

    /// The plugin's state on the main actor, shared by the plugin's view and
    /// `debugDesignOverlay()`: the mockup, how it is drawn, and whether Move is on.
    ///
    /// Main-actor isolated, like the views that read it; nothing reaches it from another thread.
    @MainActor
    final class DesignOverlayModel: ObservableObject {
        /// The model `DesignOverlay.install(mockup:)` installs and `debugDesignOverlay()` draws, over
        /// `MockupFolder.standard`. Empty until installed.
        static let shared = DesignOverlayModel(storage: MockupFolder.standard)

        /// The mockup drawn, or `nil` before one is picked.
        @Published private(set) var mockup: Mockup?
        /// How the mockup is drawn; each change is saved.
        @Published var settings = DesignOverlaySettings() {
            didSet {
                guard settings != oldValue else { return }
                storage.saveSettings(settings)
                if !settings.isVisible { isMoving = false }
            }
        }

        /// Whether a drag moves the mockup, which then takes every touch in the window. Only while
        /// the mockup shows.
        @Published var isMoving = false {
            didSet {
                if isMoving, mockup == nil || !settings.isVisible { isMoving = false }
            }
        }

        /// Why the last mockup picked couldn't be shown or saved, until the next is picked.
        @Published private(set) var failure: MockupFailure?
        /// The window's width in points, as `debugDesignOverlay()` last laid it out; `nil` before.
        @Published var windowWidth: CGFloat?

        private let storage: any MockupStorage
        private let pasteboardImage: @MainActor () -> Data?
        /// The drawers the plugin is installed in; the last to remove it takes the mockup away.
        private var installations: Set<ObjectIdentifier> = []

        /// - Parameters:
        ///   - storage: Where the mockup and settings are kept between launches.
        ///   - pasteboardImage: The image data on the pasteboard, which Paste shows; on macOS the
        ///     general pasteboard's by default, elsewhere none.
        init(storage: any MockupStorage, pasteboardImage: @escaping @MainActor () -> Data? = DesignOverlayModel.generalPasteboardImage) {
            self.storage = storage
            self.pasteboardImage = pasteboardImage
        }

        // Synchronous: install reads and decodes one file before the app's first frame (a 13-inch
        // iPad's screen at @2x takes about 20 ms in a debug build; MockupLoadTests bounds it), and a
        // load that finished later could replace a mockup handed to install.

        /// Reads the saved settings and mockup; a saved file that is no longer an image is
        /// removed.
        func load() {
            if let saved = storage.loadSettings() { settings = saved }
            guard let data = storage.loadMockup() else { return }
            do {
                mockup = try Mockup(data: data)
            } catch {
                storage.removeMockup()
            }
        }

        /// Shows `mockup` and turns the overlay on.
        ///
        /// - Parameter isSaved: Whether to save it for the next launch, replacing the saved one;
        ///   a mockup the app hands to install is shown for this launch only.
        func show(_ mockup: Mockup, isSaved: Bool) {
            self.mockup = mockup
            failure = nil
            settings.isVisible = true
            guard isSaved else { return }
            do throws(MockupFailure) {
                try storage.saveMockup(mockup.data)
            } catch {
                failure = error
            }
        }

        /// Decodes `data`, shows it and saves it; data that isn't an image leaves the mockup as it
        /// was and says why.
        func open(_ data: Data) {
            do throws(MockupFailure) {
                show(try Mockup(data: data), isSaved: true)
            } catch {
                failure = error
            }
        }

        /// Opens the image file at `url`, which the file importer picked, with the access it
        /// granted.
        func open(fileAt url: URL) {
            let isScoped = url.startAccessingSecurityScopedResource()
            defer { if isScoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else {
                failure = .unreadable
                return
            }
            open(data)
        }

        /// Opens the image on the pasteboard.
        func paste() {
            guard let data = pasteboardImage() else {
                failure = .nothingToPaste
                return
            }
            open(data)
        }

        /// Says why a picked photo or file couldn't be read.
        func fail(_ failure: MockupFailure) {
            self.failure = failure
        }

        /// Counts `drawer` as one the plugin is installed in.
        func install(in drawer: ObjectIdentifier) {
            installations.insert(drawer)
        }

        /// Uncounts `drawer`; once no drawer holds the plugin, ends Move, which takes the window's
        /// touches, and drops the mockup from memory, so nothing is drawn over the app. The saved
        /// mockup and settings stay for the next ``load()``.
        func uninstall(from drawer: ObjectIdentifier) {
            guard installations.remove(drawer) != nil, installations.isEmpty else { return }
            isMoving = false
            mockup = nil
            failure = nil
        }

        /// Removes the mockup, here and from Caches, and ends Move.
        func clear() {
            mockup = nil
            failure = nil
            isMoving = false
            storage.removeMockup()
        }

        /// Moves the mockup by a drag's `translation`.
        func move(by translation: CGSize) {
            settings = settings.moved(by: translation)
        }

        /// Shows the mockup if it is hidden, hides it if it shows.
        func toggleVisibility() {
            settings.isVisible.toggle()
        }

        /// The general pasteboard's image on macOS: an image copied from an app, or an image file
        /// copied in the Finder; `nil` elsewhere, where reading the pasteboard asks the user first.
        static func generalPasteboardImage() -> Data? {
            #if os(macOS)
                let pasteboard = NSPasteboard.general
                let imageFiles = pasteboard.readObjects(
                    forClasses: [NSURL.self],
                    options: [.urlReadingFileURLsOnly: true, .urlReadingContentsConformToTypes: [UTType.image.identifier]]
                ) as? [URL]
                if let file = imageFiles?.first, let data = try? Data(contentsOf: file) {
                    return data
                }
                return pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff)
            #else
                return nil
            #endif
        }
    }
#endif
