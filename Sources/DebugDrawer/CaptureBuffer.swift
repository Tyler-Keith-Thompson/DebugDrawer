import os

/// The newest elements a plugin captured, bounded by a count and a byte total, safe to append to
/// from any thread.
///
/// A plugin that records what the app does (log lines, requests, file calls) keeps them in a
/// capture buffer. Each appended element gets a stable ``ElementID``. When the buffer holds more
/// than ``maxCount`` elements, or their byte costs add up to more than ``maxByteCount``, it evicts
/// the oldest until both bounds hold again, and counts what it evicted, so the plugin can say how
/// many older entries were dropped. Every change bumps ``generation``, so a view can tell at a
/// glance whether anything changed. ``snapshot()`` copies the buffer out as a ``Snapshot`` value,
/// which is `Codable` when the elements are, for export and transport.
///
/// ```swift
/// let lines = try CaptureBuffer<String>(maxCount: 2_000, maxByteCount: 4_194_304) { $0.utf8.count }
/// lines.append("Loaded 25 items")   // from any thread
/// let shown = lines.snapshot()      // on the main actor, for the view
/// Text("\(shown.evictedCount) older lines dropped")
/// ```
///
/// In builds without `DEBUG` a capture buffer keeps nothing: ``append(_:)`` returns an ID and
/// stores nothing, and every snapshot is empty.
public final class CaptureBuffer<Element: Sendable>: Sendable {
    /// An element's identity in its buffer: assigned on append, in increasing order, never reused,
    /// even after ``removeAll()``.
    public struct ElementID: Hashable, Comparable, Sendable, Codable {
        /// The position of the element among every element ever appended to the buffer, from 0.
        public let rawValue: UInt64

        /// The ID with the given raw value.
        public init(rawValue: UInt64) {
            self.rawValue = rawValue
        }

        public static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.rawValue < rhs.rawValue
        }

        public init(from decoder: any Decoder) throws {
            rawValue = try decoder.singleValueContainer().decode(UInt64.self)
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(rawValue)
        }
    }

    /// The buffer's contents at one generation, as a value: all of them, or those from an ID on.
    public struct Snapshot: Sendable {
        /// The elements, oldest first.
        public let elements: [Element]
        /// The ID of the first element; the next ones follow it by one each. When there are no
        /// elements, the ID the next appended element gets.
        public let firstID: ElementID
        /// The ID of the oldest element the buffer held: ``firstID`` for a whole snapshot, and
        /// for one from an ID, where a list built from earlier snapshots now starts. When the
        /// buffer was empty, the ID the next appended element gets.
        public let oldestID: ElementID
        /// The buffer's ``CaptureBuffer/generation`` when the snapshot was taken.
        public let generation: UInt64
        /// How many elements the bounds evicted since the buffer was made or last emptied.
        public let evictedCount: Int
        /// The byte costs of the elements the bounds evicted, added up.
        public let evictedByteCount: Int
        /// The byte costs of every element the buffer held, added up; at most its
        /// ``CaptureBuffer/maxByteCount``.
        public let byteCount: Int

        /// A snapshot of `elements`, the first of them with `firstID`, of a buffer whose oldest
        /// element had `oldestID`.
        public init(
            elements: [Element],
            firstID: ElementID,
            oldestID: ElementID,
            generation: UInt64,
            evictedCount: Int,
            evictedByteCount: Int,
            byteCount: Int
        ) {
            self.elements = elements
            self.firstID = firstID
            self.oldestID = oldestID
            self.generation = generation
            self.evictedCount = evictedCount
            self.evictedByteCount = evictedByteCount
            self.byteCount = byteCount
        }

        /// The ID after the last element's: where a snapshot of what comes next starts
        /// (``CaptureBuffer/snapshot(from:)``).
        public var endID: ElementID {
            id(at: elements.count)
        }

        /// How many of a list's `count` elements, the ones with the IDs just below `end`, the
        /// buffer still held: those from ``oldestID`` on. A list built from earlier snapshots
        /// keeps that many of its newest elements and adds ``elements``.
        ///
        /// - Complexity: O(1).
        public func keptCount(of count: Int, before end: ElementID) -> Int {
            Int(min(end.rawValue - min(oldestID.rawValue, end.rawValue), UInt64(count)))
        }

        /// The ID of the element at `index` in ``elements``.
        ///
        /// - Complexity: O(1).
        public func id(at index: Int) -> ElementID {
            ElementID(rawValue: firstID.rawValue + UInt64(index))
        }

        /// The index in ``elements`` of the element with `id`, or `nil` when the snapshot doesn't
        /// hold it.
        ///
        /// - Complexity: O(1).
        public func index(of id: ElementID) -> Int? {
            guard id >= firstID else { return nil }
            let offset = id.rawValue - firstID.rawValue
            return offset < UInt64(elements.count) ? Int(offset) : nil
        }
    }

    /// The most elements the buffer keeps; ``setMaxCount(_:)`` changes it.
    public var maxCount: Int {
        state.withLockUnchecked { $0.maxCount }
    }

    /// The most the byte costs of the kept elements add up to; ``setMaxByteCount(_:)`` changes it.
    public var maxByteCount: Int {
        state.withLockUnchecked { $0.maxByteCount }
    }

    /// Keeps at most `maxCount` elements from now on; a lower bound evicts the oldest now.
    ///
    /// - Parameter maxCount: The most elements kept.
    /// - Throws: ``InvalidLimit/negativeMaxCount`` when `maxCount` is negative, changing nothing.
    public func setMaxCount(_ maxCount: Int) throws(InvalidLimit) {
        guard maxCount >= 0 else { throw .negativeMaxCount }
        state.withLockUnchecked { state in
            state.maxCount = maxCount
            if state.evictPastBounds() { state.generation &+= 1 }
        }
    }

    /// Keeps elements whose byte costs add up to at most `maxByteCount` from now on; a lower bound
    /// evicts the oldest now.
    ///
    /// - Parameter maxByteCount: The most the kept elements' byte costs add up to.
    /// - Throws: ``InvalidLimit/negativeMaxByteCount`` when `maxByteCount` is negative, changing
    ///   nothing.
    public func setMaxByteCount(_ maxByteCount: Int) throws(InvalidLimit) {
        guard maxByteCount >= 0 else { throw .negativeMaxByteCount }
        state.withLockUnchecked { state in
            state.maxByteCount = maxByteCount
            if state.evictPastBounds() { state.generation &+= 1 }
        }
    }

    /// A number that grows with every change: an append, an update, an eviction from a lowered
    /// bound, a ``removeAll()``. Equal generations mean equal contents.
    public var generation: UInt64 {
        state.withLockUnchecked { $0.generation }
    }

    // Behind a lock rather than on an actor or the main actor: the Disk I/O plugin appends from
    // swizzled calls on any thread, which must return at once, and an actor hop per call would be
    // a task per call that could reorder calls made back to back. `OSAllocatedUnfairLock` rather
    // than `Mutex`, which needs iOS 18; switch to `Mutex` once iOS 18 is the minimum.
    private let state: OSAllocatedUnfairLock<State>

    /// An empty buffer that keeps at most `maxCount` elements whose `byteCount`s add up to at most
    /// `maxByteCount`.
    ///
    /// - Parameters:
    ///   - maxCount: The most elements kept.
    ///   - maxByteCount: The most the kept elements' byte costs add up to; no bound by default.
    ///   - byteCount: An element's cost in bytes: roughly what it holds in memory, such as a log
    ///     line's text or a request's bodies. Called once per append and per update, under the
    ///     buffer's lock, so it must not call back into the buffer. Every element costs 0 by
    ///     default.
    /// - Throws: ``InvalidLimit/negativeMaxCount`` or ``InvalidLimit/negativeMaxByteCount`` when
    ///   that bound is negative.
    public convenience init(
        maxCount: Int,
        maxByteCount: Int = .max,
        byteCount: @escaping @Sendable (Element) -> Int = { _ in 0 }
    ) throws(InvalidLimit) {
        guard maxCount >= 0 else { throw .negativeMaxCount }
        guard maxByteCount >= 0 else { throw .negativeMaxByteCount }
        self.init(uncheckedMaxCount: maxCount, maxByteCount: maxByteCount, byteCount: byteCount)
    }

    /// An empty buffer whose bounds the caller knows aren't negative: a plugin's own constants,
    /// which no input reaches.
    package init(
        uncheckedMaxCount maxCount: Int,
        maxByteCount: Int = .max,
        byteCount: @escaping @Sendable (Element) -> Int = { _ in 0 }
    ) {
        state = OSAllocatedUnfairLock(uncheckedState: State(maxCount: maxCount, maxByteCount: maxByteCount, byteCount: byteCount))
    }

    /// Adds `element` as the newest, then evicts the oldest elements until both bounds hold; an
    /// element that alone costs more than ``maxByteCount`` is evicted at once.
    ///
    /// Safe to call from any thread.
    ///
    /// - Returns: The element's ID.
    /// - Complexity: Amortized O(1), plus O(*k*) for *k* evictions.
    @discardableResult
    public func append(_ element: Element) -> ElementID {
        #if DEBUG
            state.withLockUnchecked { state in
                let id = state.add(element)
                state.evictPastBounds()
                state.generation &+= 1
                return id
            }
        #else
            ElementID(rawValue: 0)
        #endif
    }

    /// Adds `elements` as the newest, in order, then evicts the oldest until both bounds hold; one
    /// change to ``generation`` for all of them.
    ///
    /// Safe to call from any thread.
    ///
    /// - Complexity: Amortized O(*n*) for *n* elements, plus O(*k*) for *k* evictions.
    public func append(contentsOf elements: some Sequence<Element>) {
        #if DEBUG
            state.withLockUnchecked { state in
                var added = false
                for element in elements {
                    state.add(element)
                    added = true
                }
                guard added else { return }
                state.evictPastBounds()
                state.generation &+= 1
            }
        #endif
    }

    /// Changes the element with `id` in place, works out its byte cost again, and evicts the
    /// oldest elements until both bounds hold.
    ///
    /// `body` runs under the buffer's lock, so it must not call back into the buffer.
    ///
    /// - Returns: Whether the buffer still held the element.
    /// - Complexity: O(1), plus O(*k*) for *k* evictions.
    @discardableResult
    public func update(_ id: ElementID, _ body: (inout Element) -> Void) -> Bool {
        #if DEBUG
            state.withLockUnchecked { state in
                guard let index = state.slotIndex(of: id) else { return false }
                // A live slot always holds its element (see `State`).
                body(&state.slots[index].element!)
                let cost = state.byteCount(state.slots[index].element!)
                state.bytes += cost - state.slots[index].cost
                state.slots[index].cost = cost
                state.evictPastBounds()
                state.generation &+= 1
                return true
            }
        #else
            false
        #endif
    }

    /// Removes every element and starts the eviction counts over. IDs keep increasing.
    public func removeAll() {
        state.withLockUnchecked { state in
            state.slots.removeAll(keepingCapacity: true)
            state.head = 0
            state.bytes = 0
            state.evictedCount = 0
            state.evictedByteCount = 0
            state.generation &+= 1
        }
    }

    /// The buffer's contents now, as a value.
    ///
    /// Safe to call from any thread.
    ///
    /// - Complexity: O(*n*) in the number of elements kept.
    public func snapshot() -> Snapshot {
        snapshot(from: ElementID(rawValue: 0))
    }

    /// The elements the buffer holds now from `id` on, as a value, with the ID of the oldest it
    /// holds.
    ///
    /// A list kept up to date with these costs only what changed since the last one: ask from the
    /// last snapshot's ``Snapshot/endID``, keep ``Snapshot/keptCount(of:before:)`` of the listed
    /// elements, and add the new ``Snapshot/elements``. Safe to call from any thread.
    ///
    /// - Complexity: O(*k*) in the number of elements from `id` on.
    public func snapshot(from id: ElementID) -> Snapshot {
        state.withLockUnchecked { state in
            let oldestID = state.nextID - UInt64(state.count)
            let firstID = min(max(id.rawValue, oldestID), state.nextID)
            let start = state.head + Int(firstID - oldestID)
            // Indexed rather than `slots[start...].map`: reading a generic element through the
            // slice's `read` coroutine allocates, once per element.
            var elements: [Element] = []
            elements.reserveCapacity(state.slots.count - start)
            for index in start ..< state.slots.count {
                // A live slot always holds its element (see `State`).
                elements.append(state.slots[index].element!)
            }
            return Snapshot(
                elements: elements,
                firstID: ElementID(rawValue: firstID),
                oldestID: ElementID(rawValue: oldestID),
                generation: state.generation,
                evictedCount: state.evictedCount,
                evictedByteCount: state.evictedByteCount,
                byteCount: state.bytes
            )
        }
    }
}

extension CaptureBuffer.Snapshot: Equatable where Element: Equatable {}

extension CaptureBuffer.Snapshot: Codable where Element: Codable {}

extension CaptureBuffer {
    /// An element with its byte cost, worked out once; `nil` once evicted, so an evicted element's
    /// memory goes at once rather than when its slot is dropped.
    private struct Slot {
        var element: Element?
        var cost: Int
    }

    /// What the lock guards.
    ///
    /// The live elements are `slots[head...]`, each slot holding its element: eviction empties
    /// the slot at `head` and moves `head` forward, and the emptied slots are dropped in one shift
    /// once they make up half the array, so eviction is amortized O(1). Hand-written rather than
    /// swift-collections' `Deque`: core takes no package dependencies.
    private struct State {
        var maxCount: Int
        var maxByteCount: Int
        let byteCount: @Sendable (Element) -> Int
        var slots: [Slot] = []
        var head = 0
        var bytes = 0
        var nextID: UInt64 = 0
        var generation: UInt64 = 0
        var evictedCount = 0
        var evictedByteCount = 0

        var count: Int {
            slots.count - head
        }

        @discardableResult
        mutating func add(_ element: Element) -> ElementID {
            let cost = byteCount(element)
            slots.append(Slot(element: element, cost: cost))
            bytes += cost
            defer { nextID += 1 }
            return ElementID(rawValue: nextID)
        }

        func slotIndex(of id: ElementID) -> Int? {
            let firstID = nextID - UInt64(count)
            guard id.rawValue >= firstID, id.rawValue < nextID else { return nil }
            return head + Int(id.rawValue - firstID)
        }

        /// Evicts the oldest elements until both bounds hold, and says whether it evicted any.
        @discardableResult
        mutating func evictPastBounds() -> Bool {
            var evicted = false
            while count > maxCount || (bytes > maxByteCount && count > 0) {
                let cost = slots[head].cost
                slots[head].element = nil
                bytes -= cost
                evictedCount += 1
                evictedByteCount += cost
                head += 1
                evicted = true
            }
            guard evicted else { return false }
            if head == slots.count {
                slots.removeAll(keepingCapacity: true)
                head = 0
            } else if head >= slots.count / 2 {
                slots.removeFirst(head)
                head = 0
            }
            return true
        }
    }
}
