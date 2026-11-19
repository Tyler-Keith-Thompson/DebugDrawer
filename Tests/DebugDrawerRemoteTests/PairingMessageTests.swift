#if DEBUG
    @testable import DebugDrawerRemote
    import Foundation
    import Testing

    @Suite
    struct PairingMessageTests {
        @Test("A pairing request encodes to JSON with sorted keys and decodes equal")
        func requestRoundTrips() throws {
            let message = PairingMessage(pairing: .request, viewerName: "Studio Mac")
            let expectedJSON = #"{"pairing":"request","version":1,"viewerName":"Studio Mac"}"#

            let encoded = message.encoded()
            let actual = PairingMessage.decoded(from: encoded)

            #expect(String(bytes: encoded, encoding: .utf8) == expectedJSON)
            #expect(actual == message)
        }

        @Test("A rejection carries its reason")
        func rejectionRoundTrips() {
            let message = PairingMessage(pairing: .rejected, rejection: .wrongCode)

            let actual = PairingMessage.decoded(from: message.encoded())

            #expect(actual?.rejection == .wrongCode)
        }

        @Test("A message of another version, or not a pairing message at all, reads as nothing")
        func otherVersionsAreDropped() {
            let otherVersion = Data(#"{"pairing":"accepted","version":2}"#.utf8)
            let transportMessage = Data(#"{"kind":"subscribe","payload":"","pluginID":"Counter","version":1}"#.utf8)

            let actual = [PairingMessage.decoded(from: otherVersion), PairingMessage.decoded(from: transportMessage)]

            #expect(actual == [nil, nil])
        }
    }
#endif
