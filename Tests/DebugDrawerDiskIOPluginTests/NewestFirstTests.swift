import Combine
@testable import DebugDrawerDiskIOPlugin
import Testing

@Suite
struct NewestFirstTests {
    @Test("A new list is empty")
    func empty() {
        var sut = NewestFirst<Int>()

        let actual = sut.wrappedValue

        #expect(actual.isEmpty)
        #expect(sut.count == 0)
    }

    @Test("Added elements read newest first")
    func readsNewestFirst() {
        var sut = NewestFirst<Int>()
        let expected = [3, 2, 1]

        sut.update(keepingNewest: 0, appending: [1, 2, 3])

        #expect(sut.wrappedValue == expected)
        #expect(sut.count == 3)
    }

    @Test("An update keeps the newest elements it is told to and drops the oldest")
    func keepsNewest() {
        var sut = NewestFirst<Int>()
        sut.update(keepingNewest: 0, appending: [1, 2, 3])
        let expected = [5, 4, 3]

        sut.update(keepingNewest: 1, appending: [4, 5])

        #expect(sut.wrappedValue == expected)
    }

    @Test("Keeping every element and adding none leaves the list as it was")
    func keepsAll() {
        var sut = NewestFirst<Int>()
        sut.update(keepingNewest: 0, appending: [1, 2])
        let expected = [2, 1]

        sut.update(keepingNewest: 2, appending: [])

        #expect(sut.wrappedValue == expected)
    }

    @Test("Keeping none and adding none empties the list")
    func keepsNone() {
        var sut = NewestFirst<Int>()
        sut.update(keepingNewest: 0, appending: [1, 2])

        sut.update(keepingNewest: 0, appending: [])

        #expect(sut.wrappedValue.isEmpty)
    }

    @Test("A list read before a change reads the change after it")
    func readAfterChange() {
        var sut = NewestFirst<Int>()
        sut.update(keepingNewest: 0, appending: [1])
        _ = sut.wrappedValue
        let expected = [2, 1]

        sut.update(keepingNewest: 1, appending: [2])

        #expect(sut.wrappedValue == expected)
    }

    @Test("The publisher sends the list newest first when subscribed, then after every change")
    func publisher() {
        var sut = NewestFirst<Int>()
        sut.update(keepingNewest: 0, appending: [1])
        var actual: [[Int]] = []
        let subscription = sut.projectedValue.sink { actual.append($0) }
        let expected = [[1], [2, 1], [3, 2]]

        sut.update(keepingNewest: 1, appending: [2])
        sut.update(keepingNewest: 1, appending: [3])

        #expect(actual == expected)
        subscription.cancel()
    }

    @Test("Two subscribers to the publisher each get every change")
    func twoSubscribers() {
        var sut = NewestFirst<Int>()
        var first: [[Int]] = []
        var second: [[Int]] = []
        let firstSubscription = sut.projectedValue.sink { first.append($0) }
        let secondSubscription = sut.projectedValue.sink { second.append($0) }
        let expected = [[], [1]]

        sut.update(keepingNewest: 0, appending: [1])

        #expect(first == expected)
        #expect(second == expected)
        firstSubscription.cancel()
        secondSubscription.cancel()
    }
}
