// ViewInspector is linked on Apple platforms only, and the views are tested on the Mac.
#if os(macOS)
    @testable import DebugDrawerRemote
    import Foundation
    import SwiftUI
    import Testing
    import ViewInspector

    // One pairing request's row over a fixture request: what VoiceOver reads for its code and its
    // Reject button.
    @MainActor
    @Suite
    struct RemotePairingRequestRowTests {
        @Test("The code 123456 shows as 123 456 and reads Code 1 2 3 4 5 6")
        func codeReadsDigitByDigit() throws {
            let request = DebugDrawerPairingRequest(id: UUID(), viewerName: "Studio Mac", code: "123456")
            let sut = RemotePairingRequestRow(request: request) {}

            let actual = try sut.inspect().find(text: "123 456").accessibilityLabel().string()

            let expected = "Code 1 2 3 4 5 6"
            #expect(actual == expected)
        }

        @Test("Reject reads Reject and the viewer's name, and tapping it rejects that request")
        func rejectNamesItsViewer() throws {
            let request = DebugDrawerPairingRequest(id: UUID(), viewerName: "Studio Mac", code: "123456")
            var rejected = 0
            let sut = RemotePairingRequestRow(request: request) { rejected += 1 }

            let button = try sut.inspect().find(button: "Reject")
            let actual = try button.accessibilityLabel().string()
            try button.tap()

            let expected = "Reject Studio Mac"
            let expectedRejections = 1
            #expect(actual == expected)
            #expect(rejected == expectedRejections)
        }
    }
#endif
