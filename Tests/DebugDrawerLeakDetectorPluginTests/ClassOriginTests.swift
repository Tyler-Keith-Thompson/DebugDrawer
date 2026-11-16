#if DEBUG
    @testable import DebugDrawerLeakDetectorPlugin
    import Foundation
    import Testing

    @Suite
    struct ClassOriginTests {
        @Test("Code under /System or /usr/lib is the system's", arguments: [
            "/System/Library/Frameworks/UIKit.framework/UIKit",
            "/System/Library/Frameworks/SwiftUI.framework/Versions/A/SwiftUI",
            "/usr/lib/swift/libswiftCore.dylib"
        ])
        func system(path: String) {
            let actual = ClassOrigin(imagePath: path)

            #expect(actual == .system)
        }

        @Test("Code under the simulator runtime's root is the system's")
        func simulatorSystem() {
            let path = "/Library/Developer/CoreSimulator/Volumes/iOS_23A343/Library/Developer/CoreSimulator/Profiles/Runtimes/"
                + "iOS 26.0.simruntime/Contents/Resources/RuntimeRoot/System/Library/Frameworks/UIKit.framework/UIKit"

            let actual = ClassOrigin(imagePath: path)

            #expect(actual == .system)
        }

        @Test("The app's executable and the frameworks it ships are the app's", arguments: [
            "/private/var/containers/Bundle/Application/1F2E/Example.app/Example",
            "/Users/someone/Library/Developer/CoreSimulator/Devices/F19E/data/Containers/Bundle/Application/9A/Example.app/Frameworks/P.framework/P",
            "/Applications/Example.app/Contents/MacOS/Example"
        ])
        func app(path: String) {
            let actual = ClassOrigin(imagePath: path)

            #expect(actual == .app)
        }

        @Test("A class with no image, such as a generic specialization made at run time, is the system's")
        func noImage() {
            let actual = ClassOrigin(imagePath: nil)

            #expect(actual == .system)
        }

        @Test("A class of the test's own is the app's, and Foundation's is the system's")
        func realClasses() {
            final class ProfileModel {}

            let actual = [ClassOrigin(of: ProfileModel.self), ClassOrigin(of: NSObject.self), ClassOrigin(of: JSONDecoder.self)]

            #expect(actual == [.app, .system, .system])
        }
    }
#endif
