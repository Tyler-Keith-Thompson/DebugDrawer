import Combine

// `@Published` can't deprecate its setter alone, and a computed `isOpen` beside a stored
// `@Published` value would lose `$isOpen`, whose name only a property wrapper can supply. So this
// wrapper keeps `@Published`'s reading and `$isOpen` (the same `Published<Bool>.Publisher`) and
// deprecates the setter on its enclosing-instance subscript, which Swift reports where a caller
// sets the wrapped property. Rejected: a read-only `isOpen` (setting it would stop compiling), a
// second property with another name (hosts reading `isOpen` and `$isOpen` would have to move).
// It holds a `@Published` value in a class of its own: `ObservableObject` finds only top-level
// `@Published` properties, so the subscript sends the drawer's `objectWillChange` itself, as
// `@Published` does, before the value and `$isOpen` change.

/// The storage of ``DebugDrawer/isOpen``: `@Published`, with a setter that warns callers to
/// call ``DebugDrawer/open()``, ``DebugDrawer/close()`` or ``DebugDrawer/toggle()`` instead.
/// The drawer sets the value through ``value``, which doesn't warn.
@propertyWrapper
struct DrawerOpenState {
    /// The value and the publisher `$isOpen` hands out.
    final class Storage {
        @Published var value: Bool

        init(_ value: Bool) {
            self.value = value
        }
    }

    private let storage: Storage

    init(wrappedValue: Bool) {
        storage = Storage(wrappedValue)
    }

    /// The value, which the drawer sets without the deprecation; a caller doing so sends the
    /// drawer's `objectWillChange` first.
    var value: Bool {
        get { storage.value }
        nonmutating set { storage.value = newValue }
    }

    /// Unused: a property of a class reads and sets the value through the enclosing-instance
    /// subscript.
    var wrappedValue: Bool {
        get { storage.value }
        nonmutating set { storage.value = newValue }
    }

    // Get-only: `@Published` lets `$isOpen` be assigned another publisher, which would cut off every
    // subscriber, and a setter here would reach hosts only if this type were public.
    /// `$isOpen`: the value now and each change, sent before it is stored, as `@Published`'s.
    var projectedValue: Published<Bool>.Publisher {
        storage.$value
    }

    static subscript<Enclosing: ObservableObject>(
        _enclosingInstance object: Enclosing,
        wrapped _: ReferenceWritableKeyPath<Enclosing, Bool>,
        storage storageKeyPath: ReferenceWritableKeyPath<Enclosing, Self>
    ) -> Bool where Enclosing.ObjectWillChangePublisher == ObservableObjectPublisher {
        get { object[keyPath: storageKeyPath].storage.value }
        @available(*, deprecated, message: "Call open(), close() or toggle()")
        set {
            object.objectWillChange.send()
            object[keyPath: storageKeyPath].storage.value = newValue
        }
    }
}
