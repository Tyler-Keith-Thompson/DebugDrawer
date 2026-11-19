#if DEBUG
    import Combine
    import DebugDrawer
    import Foundation
    import Testing

    /// A model whose snapshot is a tally and a note, changed by commands.
    @MainActor
    private final class TallyModel: DebugDrawerPluginModel {
        struct Snapshot: Codable, Equatable, Sendable {
            var count = 0
            var note = ""
        }

        enum Command: Codable, Equatable, Sendable {
            case add(Int)
            case note(String)
        }

        @Published private(set) var snapshot = Snapshot()

        func perform(_ command: Command) {
            switch command {
            case let .add(amount): snapshot.count += amount
            case let .note(text): snapshot.note = text
            }
        }
    }

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct PluginTransportTests {
        @Test("A direct transport's snapshot is the model's, and a command sent through it lands before send returns")
        func directSendLandsAtOnce() {
            let model = TallyModel()
            let sut = DebugDrawerPluginTransport.direct(to: model)
            let expected = TallyModel.Snapshot(count: 3, note: "hello")

            sut.send(.add(3))
            sut.send(.note("hello"))

            #expect(sut.snapshot == expected)
            #expect(model.snapshot == expected)
        }

        @Test("A direct transport announces each change of its model, so a view observing it draws again")
        func directForwardsChanges() {
            let model = TallyModel()
            let sut = DebugDrawerPluginTransport.direct(to: model)
            var announcements = 0
            let subscription = sut.objectWillChange.sink { announcements += 1 }

            model.perform(.add(1))
            sut.send(.add(1))

            subscription.cancel()
            #expect(announcements == 2)
        }

        @Test("snapshots() delivers the current snapshot first, then the snapshot after each change")
        func snapshotsFollowChanges() async {
            let model = TallyModel()
            model.perform(.add(1))
            let sut = DebugDrawerPluginTransport.direct(to: model)
            var iterator = sut.snapshots().makeAsyncIterator()

            let first = await iterator.next()
            sut.send(.add(2))
            let second = await iterator.next()
            model.perform(.note("done"))
            let third = await iterator.next()

            #expect(first == TallyModel.Snapshot(count: 1))
            #expect(second == TallyModel.Snapshot(count: 3))
            #expect(third == TallyModel.Snapshot(count: 3, note: "done"))
        }

        @Test("Changes made while the reader is away arrive as one snapshot holding all of them")
        func snapshotsFoldChanges() async {
            let model = TallyModel()
            let sut = DebugDrawerPluginTransport.direct(to: model)
            var iterator = sut.snapshots().makeAsyncIterator()
            let expected = TallyModel.Snapshot(count: 6, note: "three changes")

            _ = await iterator.next()
            sut.send(.add(2))
            sut.send(.add(4))
            sut.send(.note("three changes"))
            let actual = await iterator.next()

            #expect(actual == expected)
        }

        @Test("A streamed transport shows its initial snapshot, then each one the stream delivers, and hands commands to its closure")
        func streamedTransport() async {
            let (stream, continuation) = AsyncStream<TallyModel.Snapshot>.makeStream()
            var sent: [TallyModel.Command] = []
            let initial = TallyModel.Snapshot(count: 0, note: "connecting")
            let delivered = TallyModel.Snapshot(count: 7, note: "connected")
            let sut = DebugDrawerPluginTransport(initial: initial, snapshots: stream) { sent.append($0) }
            var updates = sut.snapshots().makeAsyncIterator()

            let first = await updates.next()
            continuation.yield(delivered)
            let second = await updates.next()
            sut.send(.add(1))

            #expect(first == initial)
            #expect(second == delivered)
            #expect(sut.snapshot == delivered)
            #expect(sent == [.add(1)])
            continuation.finish()
        }

        @Test("A snapshot read from snapshots() on one side and fed to a streamed transport on the other shows there, encoded between")
        func snapshotsCrossAnEncodedConnection() async throws {
            let model = TallyModel()
            let near = DebugDrawerPluginTransport.direct(to: model)
            let (wire, connection) = AsyncStream<Data>.makeStream()
            let (decoded, decodedContinuation) = AsyncStream<TallyModel.Snapshot>.makeStream()
            let far = DebugDrawerPluginTransport(initial: TallyModel.Snapshot(), snapshots: decoded) { command in
                model.perform(command)
            }
            var outgoing = near.snapshots().makeAsyncIterator()
            var incoming = wire.makeAsyncIterator()
            var shown = far.snapshots().makeAsyncIterator()
            let expected = TallyModel.Snapshot(count: 5)

            _ = await shown.next()
            _ = await outgoing.next()
            far.send(.add(5))
            let changed = await outgoing.next()
            try connection.yield(JSONEncoder().encode(#require(changed)))
            let bytes = await incoming.next()
            try decodedContinuation.yield(JSONDecoder().decode(TallyModel.Snapshot.self, from: #require(bytes)))
            let actual = await shown.next()

            #expect(actual == expected)
            #expect(far.snapshot == expected)
            connection.finish()
            decodedContinuation.finish()
        }
    }
#endif
