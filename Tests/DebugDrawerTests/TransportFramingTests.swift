#if DEBUG
    @testable import DebugDrawer
    import Foundation
    import Testing

    @Suite
    struct TransportFramingTests {
        @Test("A frame is a 4-byte big-endian length, then the message's JSON")
        func frameLayout() throws {
            let message = TransportMessage(kind: .subscribe, pluginID: "Tally")
            let body = try message.encoded()

            let actual = try TransportFraming.frame(message)

            let expectedHeader: [UInt8] = [0, 0, UInt8(body.count >> 8), UInt8(body.count & 0xFF)]
            #expect(Array(actual.prefix(4)) == expectedHeader)
            #expect(actual.dropFirst(4) == body)
        }

        @Test("A message's JSON names its version, kind and plugin, with the payload as base64")
        func messageJSON() throws {
            let message = TransportMessage(kind: .command, pluginID: "Tally", payload: Data("{}".utf8))
            let expected = #"{"kind":"command","payload":"e30=","pluginID":"Tally","version":1}"#

            let actual = try String(bytes: message.encoded(), encoding: .utf8)

            #expect(actual == expected)
        }

        @Test("Frames cut at every byte boundary decode to the messages sent, in order")
        func framesAcrossEveryCut() throws {
            let messages = [
                TransportMessage(kind: .subscribe, pluginID: "A"),
                TransportMessage(kind: .snapshot, pluginID: "B", payload: Data(#"{"count":1}"#.utf8)),
                TransportMessage(kind: .command, pluginID: "C", payload: Data(#"{"add":{"_0":2}}"#.utf8))
            ]
            let stream = try messages.reduce(into: Data()) { $0.append(try TransportFraming.frame($1)) }

            for cut in 0 ... stream.count {
                var sut = TransportFrameDecoder()

                let bodies = try sut.append(stream.prefix(cut)) + sut.append(stream.dropFirst(cut))

                let actual = bodies.compactMap(TransportMessage.decoded(from:))
                #expect(actual == messages, "cut at \(cut)")
            }
        }

        @Test("An unfinished frame yields nothing until its last byte arrives")
        func unfinishedFrameWaits() throws {
            let message = TransportMessage(kind: .subscribe, pluginID: "Tally")
            let frame = try TransportFraming.frame(message)
            var sut = TransportFrameDecoder()

            let early = try sut.append(frame.dropLast())
            let late = try sut.append(frame.suffix(1))

            #expect(early.isEmpty)
            #expect(late.compactMap(TransportMessage.decoded(from:)) == [message])
        }

        @Test("An empty frame and an empty append yield an empty body and nothing")
        func emptyFrames() throws {
            var sut = TransportFrameDecoder()

            let nothing = try sut.append(Data())
            let empty = try sut.append(Data([0, 0, 0, 0]))

            #expect(nothing.isEmpty)
            #expect(empty == [Data()])
        }

        @Test("A frame of exactly the maximum length is accepted; one byte more throws FrameTooLong")
        func lengthBoundary() throws {
            let maximum = UInt32(TransportFraming.maximumLength)
            var atMaximum = TransportFrameDecoder()
            var overMaximum = TransportFrameDecoder()

            let waiting = try atMaximum.append(Data(withUnsafeBytes(of: maximum.bigEndian, Array.init)))

            #expect(waiting.isEmpty)
            #expect(throws: TransportFrameDecoder.FrameTooLong.self) {
                try overMaximum.append(Data(withUnsafeBytes(of: (maximum + 1).bigEndian, Array.init)))
            }
        }

        @Test("A body that isn't a message, or is another version's, decodes to nil")
        func unreadableBodies() throws {
            var otherVersion = TransportMessage(kind: .subscribe, pluginID: "Tally")
            otherVersion.version = TransportMessage.currentVersion + 1
            let unknownKind = Data(#"{"kind":"shout","payload":"","pluginID":"Tally","version":1}"#.utf8)

            let malformed = TransportMessage.decoded(from: Data("not json".utf8))
            let newer = try TransportMessage.decoded(from: otherVersion.encoded())
            let unknown = TransportMessage.decoded(from: unknownKind)

            #expect(malformed == nil)
            #expect(newer == nil)
            #expect(unknown == nil)
        }

        @Test("A payload encodes with its keys sorted, so an unchanged value encodes to the same bytes")
        func payloadKeysSorted() throws {
            let value = ["zebra": 1, "apple": 2, "mango": 3]
            let expected = #"{"apple":2,"mango":3,"zebra":1}"#

            let actual = try String(bytes: TransportMessage.payload(value), encoding: .utf8)

            #expect(actual == expected)
        }
    }
#endif
