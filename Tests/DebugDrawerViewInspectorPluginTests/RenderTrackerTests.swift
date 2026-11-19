#if DEBUG
    @testable import DebugDrawerViewInspectorPlugin
    import Testing

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct RenderTrackerTests {
        @Test("Each record adds one to its name's count and returns the new count")
        func recordCounts() {
            let sut = RenderTracker()
            let expected = ["FeedView": 2, "AvatarView": 1]

            let first = sut.record("FeedView")
            let second = sut.record("FeedView")
            sut.record("AvatarView")
            let actual = sut.counts

            #expect(first == 1)
            #expect(second == 2)
            #expect(actual == expected)
        }

        @Test("A new name past the capacity drops the name counted first, while a known name only counts")
        func capacityDropsTheOldestName() {
            let sut = RenderTracker()
            sut.capacity = 2
            let expected = ["AvatarView": 2, "Badge": 1]

            sut.record("FeedView")
            sut.record("AvatarView")
            sut.record("AvatarView")
            sut.record("Badge")
            let actual = sut.counts

            #expect(actual == expected)
        }

        @Test("Lowering the capacity drops the oldest names at once, and a capacity of 0 keeps none")
        func lowerCapacity() {
            let sut = RenderTracker()
            sut.record("FeedView")
            sut.record("AvatarView")
            sut.record("Badge")
            let expectedAfterLowering: [String: Int] = ["Badge": 1]

            sut.capacity = 1
            let afterLowering = sut.counts
            sut.capacity = 0
            sut.record("SettingsView")
            let actual = sut.counts

            #expect(afterLowering == expectedAfterLowering)
            #expect(actual.isEmpty)
        }

        @Test("Entries list the busiest first, and names in order among equal counts")
        func busiestFirst() {
            let counts = ["SettingsView": 2, "FeedView": 24, "AvatarView": 2, "Badge": 7]
            let expected = [
                RenderTracker.Entry(id: "FeedView", count: 24),
                RenderTracker.Entry(id: "Badge", count: 7),
                RenderTracker.Entry(id: "AvatarView", count: 2),
                RenderTracker.Entry(id: "SettingsView", count: 2)
            ]

            let actual = RenderTracker.Entry.busiestFirst(counts)

            #expect(actual == expected)
        }

        @Test("No counts make no entries")
        func noCounts() {
            let actual = RenderTracker.Entry.busiestFirst([:])

            #expect(actual.isEmpty)
        }

        @Test("Records leave the published entries alone until the main queue's next turn, which publishes them all at once")
        func publishesOnTheNextTurn() async {
            let sut = RenderTracker()
            let expected = [RenderTracker.Entry(id: "FeedView", count: 3)]
            var published: [[RenderTracker.Entry]] = []
            let subscription = sut.$entries.dropFirst().sink { published.append($0) }

            sut.record("FeedView")
            sut.record("FeedView")
            sut.record("FeedView")
            let beforeTheTurn = sut.entries
            for await entries in sut.$entries.values where !entries.isEmpty {
                break
            }
            subscription.cancel()

            #expect(beforeTheTurn.isEmpty)
            #expect(published == [expected])
        }

        @Test("Reset forgets the counts and the published entries")
        func reset() async {
            let sut = RenderTracker()
            sut.record("FeedView")
            for await entries in sut.$entries.values where !entries.isEmpty {
                break
            }

            sut.reset()

            #expect(sut.counts.isEmpty)
            #expect(sut.entries.isEmpty)
        }
    }
#endif
