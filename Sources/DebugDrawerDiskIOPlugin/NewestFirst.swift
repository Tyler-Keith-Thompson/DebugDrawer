import Combine

// In place of `@Published`, whose setter takes a whole new array: with the main thread idle each
// file call is a delivery of its own, and building a new 500-event array for each copied and
// released every event, where changing this one in place moves them.

/// A list read newest first and kept oldest first, so that adding to its newest end and dropping
/// from its oldest end change it in place: the storage of ``DiskIOStore/events``.
///
/// The newest-first array is built when something reads the list, once per change. The projected
/// publisher, the one `@Published` projects, is made when something first asks for it; from then
/// on each change sends the list through it, newest first.
///
/// Its owner sends `objectWillChange` itself before it changes the list. Release builds keep the
/// type, unused, so the module's public API is the same in every build.
@propertyWrapper
public struct NewestFirst<Element> {
    /// The elements, oldest first.
    private var oldestFirst: [Element] = []
    /// The elements newest first, built at the first read after a change.
    private var newestFirst: [Element]? = []
    private var published: Published<[Element]>?
    private var changes: PassthroughSubject<[Element], Never>?

    /// An empty list.
    public init() {}

    /// The elements, newest first.
    ///
    /// - Complexity: O(*n*) at the first read after a change; O(1) after that.
    public var wrappedValue: [Element] {
        mutating get {
            if let newestFirst { return newestFirst }
            let built = Array(oldestFirst.reversed())
            newestFirst = built
            return built
        }
    }

    /// The list, newest first, now and after each change.
    public var projectedValue: Published<[Element]>.Publisher {
        mutating get {
            if published == nil {
                var made = Published(initialValue: wrappedValue)
                let changes = PassthroughSubject<[Element], Never>()
                changes.assign(to: &made.projectedValue)
                self.changes = changes
                published = made
            }
            // Set just above when it was nil.
            return published!.projectedValue
        }
    }

    /// How many elements the list holds.
    var count: Int {
        oldestFirst.count
    }

    /// Keeps the newest `kept` elements and adds `newer`, oldest first, after them.
    ///
    /// - Complexity: O(*n*) moves when it drops any, and O(*m*) copies for the *m* it adds.
    mutating func update(keepingNewest kept: Int, appending newer: some Collection<Element>) {
        oldestFirst.removeFirst(oldestFirst.count - kept)
        oldestFirst.append(contentsOf: newer)
        newestFirst = nil
        changes?.send(wrappedValue)
    }
}
