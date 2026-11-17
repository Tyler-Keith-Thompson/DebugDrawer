#if DEBUG
    import CoreGraphics
    @testable import DebugDrawerDesignOverlayPlugin
    import Foundation
    import Testing

    @MainActor
    @Suite
    struct DesignOverlayModelTests {
        @Test("Loading reads the saved settings and mockup")
        func load() {
            var saved = DesignOverlaySettings()
            saved.opacity = 0.8
            saved.blend = .difference
            let storage = FakeMockupStorage(mockup: MockupFixture.png(width: 30, height: 60), settings: saved)
            let sut = DesignOverlayModel(storage: storage)

            sut.load()

            #expect(sut.settings == saved)
            #expect(sut.mockup?.pixelSize == CGSize(width: 30, height: 60))
            #expect(sut.failure == nil)
        }

        @Test("Loading with nothing saved leaves the defaults and no mockup")
        func loadNothing() {
            let sut = DesignOverlayModel(storage: FakeMockupStorage())

            sut.load()

            #expect(sut.settings == DesignOverlaySettings())
            #expect(sut.mockup == nil)
        }

        @Test("A saved mockup that is no longer an image is removed at load")
        func loadCorrupt() {
            let storage = FakeMockupStorage(mockup: Data("garbage".utf8))
            let sut = DesignOverlayModel(storage: storage)

            sut.load()

            #expect(sut.mockup == nil)
            #expect(storage.mockup == nil)
        }

        @Test("Opening an image shows it, turns the overlay on and saves it; settings changes are saved")
        func openSaves() {
            let storage = FakeMockupStorage()
            let sut = DesignOverlayModel(storage: storage)
            sut.settings.isVisible = false
            let data = MockupFixture.png(width: 40, height: 80)

            sut.open(data)
            sut.settings.opacity = 0.25

            #expect(sut.mockup?.pixelSize == CGSize(width: 40, height: 80))
            #expect(sut.settings.isVisible)
            #expect(storage.mockup == data)
            #expect(storage.settings?.opacity == 0.25)
            #expect(storage.settings?.isVisible == true)
        }

        @Test("Setting the same settings again saves nothing")
        func unchangedSettings() {
            let storage = FakeMockupStorage()
            let sut = DesignOverlayModel(storage: storage)

            sut.settings = DesignOverlaySettings()

            #expect(storage.settingsSaves == 0)
        }

        @Test("Opening data that isn't an image keeps the mockup shown and says why")
        func openNotAnImage() {
            let storage = FakeMockupStorage()
            let sut = DesignOverlayModel(storage: storage)
            let data = MockupFixture.png(width: 10, height: 10)
            sut.open(data)

            sut.open(Data("nope".utf8))

            #expect(sut.mockup?.data == data)
            #expect(sut.failure == .notAnImage)
            #expect(storage.mockup == data)
        }

        @Test("A mockup that can't be saved still shows, and says it isn't saved")
        func openNotSaved() {
            let sut = DesignOverlayModel(storage: FakeMockupStorage(failsToSave: true))

            sut.open(MockupFixture.png(width: 10, height: 10))

            #expect(sut.mockup != nil)
            #expect(sut.failure == .notSaved)
        }

        @Test("Opening a good image after a failure clears the failure")
        func failureCleared() {
            let sut = DesignOverlayModel(storage: FakeMockupStorage())
            sut.open(Data())

            sut.open(MockupFixture.png(width: 10, height: 10))

            #expect(sut.failure == nil)
        }

        @Test("A mockup shown but not saved, as install's, leaves the saved one in storage")
        func showUnsaved() throws {
            let saved = MockupFixture.png(width: 10, height: 10)
            let storage = FakeMockupStorage(mockup: saved)
            let sut = DesignOverlayModel(storage: storage)

            sut.show(try Mockup(data: MockupFixture.png(width: 20, height: 20)), isSaved: false)

            #expect(sut.mockup?.pixelSize == CGSize(width: 20, height: 20))
            #expect(storage.mockup == saved)
        }

        @Test("Opening a file reads it; a file that isn't there says it couldn't be read")
        func openFile() throws {
            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let file = directory.appending(path: "Comp.png")
            try MockupFixture.png(width: 12, height: 24).write(to: file)
            let sut = DesignOverlayModel(storage: FakeMockupStorage())

            sut.open(fileAt: file)
            let opened = sut.mockup?.pixelSize
            sut.open(fileAt: directory.appending(path: "Missing.png"))

            #expect(opened == CGSize(width: 12, height: 24))
            #expect(sut.failure == .unreadable)
        }

        @Test("Paste opens the pasteboard's image; an empty pasteboard says there's nothing to paste")
        func paste() {
            let image = MockupFixture.png(width: 16, height: 8)
            let sut = DesignOverlayModel(storage: FakeMockupStorage(), pasteboardImage: { image })
            let empty = DesignOverlayModel(storage: FakeMockupStorage(), pasteboardImage: { nil })

            sut.paste()
            empty.paste()

            #expect(sut.mockup?.pixelSize == CGSize(width: 16, height: 8))
            #expect(sut.failure == nil)
            #expect(empty.mockup == nil)
            #expect(empty.failure == .nothingToPaste)
        }

        @Test("Clear removes the mockup here and in storage, and ends Move")
        func clear() {
            let storage = FakeMockupStorage()
            let sut = DesignOverlayModel(storage: storage)
            sut.open(MockupFixture.png(width: 10, height: 10))
            sut.isMoving = true

            sut.clear()

            #expect(sut.mockup == nil)
            #expect(storage.mockup == nil)
            #expect(!sut.isMoving)
        }

        @Test("Move can't be turned on with no mockup or a hidden one, and hiding the mockup ends it")
        func moveNeedsAVisibleMockup() {
            let sut = DesignOverlayModel(storage: FakeMockupStorage())

            sut.isMoving = true
            let withoutMockup = sut.isMoving
            sut.open(MockupFixture.png(width: 10, height: 10))
            sut.isMoving = true
            let withMockup = sut.isMoving
            sut.toggleVisibility()
            let afterHiding = sut.isMoving
            sut.isMoving = true
            let whileHidden = sut.isMoving

            #expect(!withoutMockup)
            #expect(withMockup)
            #expect(!afterHiding)
            #expect(!whileHidden)
        }

        @Test("A drag moves the mockup by its translation, in whole points, and the move is saved")
        func move() {
            let storage = FakeMockupStorage()
            let sut = DesignOverlayModel(storage: storage)
            sut.settings.offset = CGSize(width: 5, height: 5)
            let expected = CGSize(width: 25, height: -5)

            sut.move(by: CGSize(width: 19.7, height: -10.2))

            #expect(sut.settings.offset == expected)
            #expect(storage.settings?.offset == expected)
        }

        @Test("Toggling visibility hides a shown mockup and shows a hidden one")
        func toggle() {
            let sut = DesignOverlayModel(storage: FakeMockupStorage())

            sut.toggleVisibility()
            let hidden = sut.settings.isVisible
            sut.toggleVisibility()

            #expect(!hidden)
            #expect(sut.settings.isVisible)
        }
    }
#endif
