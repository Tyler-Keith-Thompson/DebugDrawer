#if DEBUG
    import DebugDrawer
    import Foundation
    import Testing

    struct CaptureBufferTests {
        @Test("Past maxCount, the oldest elements go and the newest stay, oldest first")
        func countBound() throws {
            let sut = try CaptureBuffer<String>(maxCount: 3)
            let expected = ["c", "d", "e"]

            for element in ["a", "b", "c", "d", "e"] {
                sut.append(element)
            }
            let actual = sut.snapshot()

            #expect(actual.elements == expected)
            #expect(actual.evictedCount == 2)
        }

        @Test("Past maxByteCount, the oldest elements go until the kept ones' costs fit")
        func byteBound() throws {
            let sut = try CaptureBuffer<String>(maxCount: 100, maxByteCount: 10) { $0.utf8.count }
            let expected = ["dddd", "eeeee"]
            let expectedBytes = 9
            let expectedEvictedBytes = 6

            for element in ["a", "bb", "ccc", "dddd", "eeeee"] {
                sut.append(element)
            }
            let actual = sut.snapshot()

            #expect(actual.elements == expected)
            #expect(actual.byteCount == expectedBytes)
            #expect(actual.evictedCount == 3)
            #expect(actual.evictedByteCount == expectedEvictedBytes)
        }

        @Test("An element that alone costs more than maxByteCount is evicted at once, with every older one")
        func elementPastByteBound() throws {
            let sut = try CaptureBuffer<String>(maxCount: 100, maxByteCount: 4) { $0.utf8.count }
            sut.append("ab")

            sut.append("too long")
            let actual = sut.snapshot()

            #expect(actual.elements.isEmpty)
            #expect(actual.byteCount == 0)
            #expect(actual.evictedCount == 2)
        }

        @Test("Evictions take the oldest first, in the order the elements were appended, across many compactions")
        func evictionOrder() throws {
            let sut = try CaptureBuffer<Int>(maxCount: 7)
            let expected = Array(993 ..< 1000)

            for element in 0 ..< 1000 {
                sut.append(element)
            }
            let actual = sut.snapshot()

            #expect(actual.elements == expected)
            #expect(actual.evictedCount == 993)
        }

        @Test("A buffer with maxCount 0 keeps nothing and counts every append as evicted")
        func zeroCount() throws {
            let sut = try CaptureBuffer<Int>(maxCount: 0)

            sut.append(contentsOf: [1, 2, 3])
            let actual = sut.snapshot()

            #expect(actual.elements.isEmpty)
            #expect(actual.evictedCount == 3)
        }

        @Test("Lowering maxCount or maxByteCount evicts the oldest now")
        func loweringBounds() throws {
            let sut = try CaptureBuffer<String>(maxCount: 10) { $0.utf8.count }
            sut.append(contentsOf: ["aa", "bb", "cc", "dd"])

            try sut.setMaxCount(3)
            let afterCount = sut.snapshot().elements
            try sut.setMaxByteCount(4)
            let afterBytes = sut.snapshot().elements

            #expect(afterCount == ["bb", "cc", "dd"])
            #expect(afterBytes == ["cc", "dd"])
        }

        @Test("IDs increase by one per append and stay with their element as older ones are evicted")
        func stableIDs() throws {
            let sut = try CaptureBuffer<String>(maxCount: 2)
            let first = sut.append("a")
            let second = sut.append("b")
            let third = sut.append("c")

            let actual = sut.snapshot()

            #expect(second.rawValue == first.rawValue + 1)
            #expect(third.rawValue == second.rawValue + 1)
            #expect(actual.firstID == second)
            #expect(actual.id(at: 1) == third)
            #expect(actual.index(of: first) == nil)
            let index = try #require(actual.index(of: third))
            #expect(actual.elements[index] == "c")
        }

        @Test("A snapshot from an ID holds the elements from it on, and names the oldest the buffer holds")
        func snapshotFrom() throws {
            let sut = try CaptureBuffer<String>(maxCount: 3)
            sut.append(contentsOf: ["a", "b", "c"])
            let earlier = sut.snapshot()
            sut.append(contentsOf: ["d", "e"])

            let actual = sut.snapshot(from: earlier.endID)

            #expect(actual.elements == ["d", "e"])
            #expect(actual.firstID == earlier.endID)
            #expect(actual.oldestID == earlier.id(at: 2))
            #expect(actual.endID.rawValue == 5)
            #expect(actual.evictedCount == 2)
        }

        @Test("A snapshot from an evicted ID starts at the oldest kept, and one from past the end is empty")
        func snapshotFromBounds() throws {
            let sut = try CaptureBuffer<String>(maxCount: 2)
            sut.append(contentsOf: ["a", "b", "c", "d"])

            let fromEvicted = sut.snapshot(from: CaptureBuffer<String>.ElementID(rawValue: 0))
            let pastEnd = sut.snapshot(from: CaptureBuffer<String>.ElementID(rawValue: 10))

            #expect(fromEvicted.elements == ["c", "d"])
            #expect(fromEvicted.firstID.rawValue == 2)
            #expect(pastEnd.elements.isEmpty)
            #expect(pastEnd.firstID.rawValue == 4)
            #expect(pastEnd.oldestID.rawValue == 2)
        }

        @Test("A list built from earlier snapshots keeps its elements from the oldest the buffer still holds")
        func keptCount() throws {
            let sut = try CaptureBuffer<String>(maxCount: 3)
            sut.append(contentsOf: ["a", "b", "c"])
            let earlier = sut.snapshot()
            sut.append(contentsOf: ["d", "e"])
            let cleared = try CaptureBuffer<String>(maxCount: 3)
            cleared.append(contentsOf: ["a", "b"])
            let clearedEarlier = cleared.snapshot()
            cleared.removeAll()

            let actual = sut.snapshot(from: earlier.endID).keptCount(of: 3, before: earlier.endID)
            let afterClear = cleared.snapshot(from: clearedEarlier.endID).keptCount(of: 2, before: clearedEarlier.endID)
            let unchanged = sut.snapshot(from: sut.snapshot().endID).keptCount(of: 3, before: sut.snapshot().endID)

            #expect(actual == 1)
            #expect(afterClear == 0)
            #expect(unchanged == 3)
        }

        @Test("An empty buffer's snapshot names the ID the next append gets")
        func emptyFirstID() throws {
            let sut = try CaptureBuffer<String>(maxCount: 1)
            sut.append("a")
            sut.removeAll()

            let expected = sut.snapshot().firstID
            let actual = sut.append("b")

            #expect(actual == expected)
            #expect(actual.rawValue == 1)
        }

        @Test("Updating an element changes it in place and counts its new cost against the byte bound")
        func update() throws {
            let sut = try CaptureBuffer<String>(maxCount: 10, maxByteCount: 6) { $0.utf8.count }
            sut.append("aa")
            let id = sut.append("b")

            let found = sut.update(id) { $0 = "bbbbb" }
            let actual = sut.snapshot()

            #expect(found)
            #expect(actual.elements == ["bbbbb"])
            #expect(actual.byteCount == 5)
            #expect(actual.evictedCount == 1)
        }

        @Test("Updating an evicted element finds nothing and changes nothing")
        func updateEvicted() throws {
            let sut = try CaptureBuffer<String>(maxCount: 1)
            let evicted = sut.append("a")
            sut.append("b")
            let before = sut.generation

            let found = sut.update(evicted) { $0 = "changed" }

            #expect(!found)
            #expect(sut.generation == before)
            #expect(sut.snapshot().elements == ["b"])
        }

        @Test("Every change bumps the generation once: an append, a batch, an update, an evicting bound, a removeAll")
        func generation() throws {
            let sut = try CaptureBuffer<Int>(maxCount: 10)
            var generations = [sut.generation]

            let id = sut.append(1)
            generations.append(sut.generation)
            sut.append(contentsOf: [2, 3, 4])
            generations.append(sut.generation)
            sut.update(id) { $0 = 10 }
            generations.append(sut.generation)
            try sut.setMaxCount(2)
            generations.append(sut.generation)
            sut.removeAll()
            generations.append(sut.generation)
            let expected: [UInt64] = [0, 1, 2, 3, 4, 5]

            #expect(generations == expected)
            #expect(sut.snapshot().generation == 5)
        }

        @Test("What changes nothing leaves the generation alone: an empty batch, a bound that evicts nothing")
        func generationUnchanged() throws {
            let sut = try CaptureBuffer<Int>(maxCount: 10)
            sut.append(1)
            let expected = sut.generation

            sut.append(contentsOf: [])
            try sut.setMaxCount(5)
            try sut.setMaxByteCount(100)

            #expect(sut.generation == expected)
        }

        @Test("removeAll empties the buffer and starts the eviction counts over")
        func removeAll() throws {
            let sut = try CaptureBuffer<Int>(maxCount: 1)
            sut.append(contentsOf: [1, 2, 3])

            sut.removeAll()
            let actual = sut.snapshot()

            #expect(actual.elements.isEmpty)
            #expect(actual.evictedCount == 0)
            #expect(actual.evictedByteCount == 0)
            #expect(actual.byteCount == 0)
        }

        @Test("A snapshot of Codable elements encodes to JSON and decodes to an equal snapshot")
        func codableRoundTrip() throws {
            struct Event: Codable, Equatable {
                let name: String
                let size: Int
            }
            let sut = try CaptureBuffer<Event>(maxCount: 2) { $0.size }
            sut.append(Event(name: "read", size: 4))
            sut.append(Event(name: "write", size: 8))
            sut.append(Event(name: "delete", size: 0))
            let expected = sut.snapshot()

            let data = try JSONEncoder().encode(expected)
            let actual = try JSONDecoder().decode(CaptureBuffer<Event>.Snapshot.self, from: data)

            #expect(actual == expected)
            #expect(actual.firstID.rawValue == 1)
            #expect(actual.evictedCount == 1)
        }

        @Test("Appends from many threads at once all land, each with its own ID, within the bound")
        func concurrentAppends() async throws {
            let sut = try CaptureBuffer<Int>(maxCount: 1000)
            let threads = 8
            let perThread = 500

            await withTaskGroup(of: [CaptureBuffer<Int>.ElementID].self) { group in
                for thread in 0 ..< threads {
                    group.addTask {
                        (0 ..< perThread).map { sut.append(thread * perThread + $0) }
                    }
                }
                var ids = Set<CaptureBuffer<Int>.ElementID>()
                for await batch in group {
                    ids.formUnion(batch)
                }
                #expect(ids.count == threads * perThread)
            }
            let actual = sut.snapshot()

            #expect(actual.elements.count == 1000)
            #expect(actual.evictedCount == threads * perThread - 1000)
            #expect(Set(actual.elements).count == 1000)
            #expect(actual.generation == UInt64(threads * perThread))
        }

        @Test("Each thread's appends keep their order in the buffer")
        func concurrentOrder() async throws {
            let sut = try CaptureBuffer<[Int]>(maxCount: 10000)
            let threads = 4
            let perThread = 1000

            await withTaskGroup(of: Void.self) { group in
                for thread in 0 ..< threads {
                    group.addTask {
                        for index in 0 ..< perThread {
                            sut.append([thread, index])
                        }
                    }
                }
            }
            let elements = sut.snapshot().elements

            for thread in 0 ..< threads {
                let actual = elements.filter { $0[0] == thread }.map { $0[1] }
                #expect(actual == Array(0 ..< perThread))
            }
        }

        @Test("A negative maxCount throws negativeMaxCount")
        func negativeMaxCount() {
            let expected = CaptureBuffer<Int>.InvalidLimit.negativeMaxCount

            #expect(throws: expected) {
                _ = try CaptureBuffer<Int>(maxCount: -1)
            }
        }

        @Test("A negative maxByteCount throws negativeMaxByteCount")
        func negativeMaxByteCount() {
            let expected = CaptureBuffer<Int>.InvalidLimit.negativeMaxByteCount

            #expect(throws: expected) {
                _ = try CaptureBuffer<Int>(maxCount: 1, maxByteCount: -1)
            }
        }

        @Test("Bounds of 0 are taken: the edge of the valid range")
        func zeroBounds() throws {
            let sut = try CaptureBuffer<Int>(maxCount: 0, maxByteCount: 0)

            #expect(sut.maxCount == 0)
            #expect(sut.maxByteCount == 0)
        }

        @Test("Setting a negative maxCount throws negativeMaxCount and keeps the bound and the elements")
        func settingNegativeMaxCount() throws {
            let sut = try CaptureBuffer<Int>(maxCount: 3)
            sut.append(contentsOf: [1, 2, 3])
            let expectedGeneration = sut.generation

            #expect(throws: CaptureBuffer<Int>.InvalidLimit.negativeMaxCount) {
                try sut.setMaxCount(-1)
            }
            #expect(sut.maxCount == 3)
            #expect(sut.snapshot().elements == [1, 2, 3])
            #expect(sut.generation == expectedGeneration)
        }

        @Test("Setting a negative maxByteCount throws negativeMaxByteCount and keeps the bound")
        func settingNegativeMaxByteCount() throws {
            let sut = try CaptureBuffer<String>(maxCount: 3, maxByteCount: 10) { $0.utf8.count }
            sut.append("abc")

            #expect(throws: CaptureBuffer<String>.InvalidLimit.negativeMaxByteCount) {
                try sut.setMaxByteCount(-1)
            }
            #expect(sut.maxByteCount == 10)
            #expect(sut.snapshot().elements == ["abc"])
        }
    }
#endif
