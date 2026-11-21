#if DEBUG
    @testable import DebugDrawer
    import Testing

    /// An object for the set to hold.
    private final class Held {}

    @Suite("Objects held weakly")
    struct WeakSetTests {
        @Test("An empty set lists nothing")
        func empty() {
            let sut = WeakSet<Held>()

            let actual = sut.allObjects

            #expect(actual.isEmpty)
        }

        @Test("Objects are listed in the order they were added, each once however often it is added")
        func addedOnceInOrder() {
            let first = Held()
            let second = Held()
            var sut = WeakSet<Held>()

            sut.add(first)
            sut.add(second)
            sut.add(first)

            let actual = sut.allObjects
            #expect(actual.count == 2)
            #expect(actual.first === first)
            #expect(actual.last === second)
        }

        @Test("A removed object is no longer listed, and removing one not in the set changes nothing")
        func removed() {
            let kept = Held()
            let removed = Held()
            let stranger = Held()
            var sut = WeakSet<Held>()
            sut.add(kept)
            sut.add(removed)

            sut.remove(removed)
            sut.remove(stranger)

            let actual = sut.allObjects
            #expect(actual.count == 1)
            #expect(actual.first === kept)
        }

        @Test("A freed object leaves the set, and an object added again after removal is listed")
        func freedLeaves() {
            let kept = Held()
            var sut = WeakSet<Held>()
            do {
                let freed = Held()
                sut.add(freed)
            }
            sut.add(kept)
            sut.remove(kept)

            sut.add(kept)

            let actual = sut.allObjects
            #expect(actual.count == 1)
            #expect(actual.first === kept)
        }

        // NSHashTable.weakObjects() failed both of these on the tvOS simulator (DD-279): its weak
        // loads autoreleased the objects, which lived on until the run loop drained the pool.
        @Test("Adding objects keeps none alive once their owners let go")
        func addingKeepsNoneAlive() {
            var sut = WeakSet<Held>()
            let expectedCount = 100
            var freed: [WeakReference] = []

            do {
                let owners = (0..<expectedCount).map { _ in Held() }
                for owner in owners {
                    sut.add(owner)
                }
                freed = owners.map(WeakReference.init)
            }

            #expect(freed.count == expectedCount)
            #expect(freed.allSatisfy { $0.object == nil })
            #expect(sut.allObjects.isEmpty)
        }

        @Test("Listing the objects keeps none alive once their owners let go")
        func listingKeepsNoneAlive() {
            var sut = WeakSet<Held>()
            weak var freed: Held?

            do {
                let owner = Held()
                sut.add(owner)
                freed = owner
                #expect(sut.allObjects.count == 1)
            }

            #expect(freed == nil)
        }
    }

    /// One object of the test's, held weakly, to see that it was freed.
    private struct WeakReference {
        weak var object: Held?

        init(_ object: Held) {
            self.object = object
        }
    }
#endif
