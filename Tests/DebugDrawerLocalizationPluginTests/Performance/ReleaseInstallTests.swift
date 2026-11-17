// The release stand-in. `--config=release` builds and runs only the performance targets, so this
// is where a test is compiled without DEBUG, as an app's release build is; in debug the file is
// empty, and LocalizationInstallExitTests checks the opposite.
#if !DEBUG
    import DebugDrawerLocalizationPlugin
    import Foundation
    import ObjectiveC
    import SwiftUI
    import Testing

    @Suite
    struct ReleaseInstallTests {
        @MainActor
        @Test("In release, install replaces no lookup and leaves every string as it is")
        func installDoesNothing() throws {
            let selector = #selector(Bundle.localizedString(forKey:value:table:))
            let method = try #require(class_getInstanceMethod(Bundle.self, selector))
            let expectedImplementation = method_getImplementation(method)
            let expected = "settings.title"

            Localization.install(mode: .pseudoLocalized)
            Localization.install(mode: .showingKeys)
            let actual = Bundle.main.localizedString(forKey: "settings.title", value: nil, table: nil)

            #expect(actual == expected)
            #expect(method_getImplementation(method) == expectedImplementation)
        }

        @MainActor
        @Test("In release, debugLocalization returns the view as it is")
        func modifierIsTheView() {
            let content = Text("Settings")

            let actual = content.debugLocalization()

            #expect(type(of: actual) == Text.self)
        }
    }
#endif
