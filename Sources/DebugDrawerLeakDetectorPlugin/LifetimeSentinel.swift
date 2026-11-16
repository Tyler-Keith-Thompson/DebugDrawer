#if DEBUG
    import Dispatch
    import ObjectiveC
    import os

    /// An object attached to a tracked one as an associated object, which the runtime releases
    /// when the tracked object deallocates: its `deinit` is how the tracker learns of the end of a
    /// lifetime, without holding a reference or polling a weak one.
    final class LifetimeSentinel: Sendable {
        /// Tells this sentinel's object apart from every other tracked in this process, even one
        /// later allocated at the same address.
        let id: UInt64
        private let onEnd: @MainActor @Sendable (UInt64) -> Void

        private init(onEnd: @escaping @MainActor @Sendable (UInt64) -> Void) {
            id = Self.nextID.withLock { next in
                defer { next += 1 }
                return next
            }
            self.onEnd = onEnd
        }

        deinit {
            let id = id
            let onEnd = onEnd
            // Through the main queue even from the main thread: an object can deallocate in the
            // middle of anything, a SwiftUI update included, where changing the drawer's state
            // isn't allowed. The queue runs blocks in the order they were added, so the end of an
            // object tracked off the main thread arrives after its start, which went the same way.
            DispatchQueue.main.async { onEnd(id) }
        }

        /// The sentinel attached to `object`, attaching a new one if it has none. A sentinel is
        /// attached once per object: the first one's `onEnd` is the one called.
        ///
        /// - Parameters:
        ///   - object: The object whose deallocation to learn of.
        ///   - onEnd: Called on the main queue with the sentinel's ``id`` once `object` deallocates.
        static func attached(to object: AnyObject, onEnd: @escaping @MainActor @Sendable (UInt64) -> Void) -> LifetimeSentinel {
            if let existing = objc_getAssociatedObject(object, key) as? LifetimeSentinel {
                return existing
            }
            let sentinel = LifetimeSentinel(onEnd: onEnd)
            objc_setAssociatedObject(object, key, sentinel, .OBJC_ASSOCIATION_RETAIN)
            return sentinel
        }

        /// `OSAllocatedUnfairLock` rather than `Mutex`, which needs iOS 18: objects are tracked from
        /// any thread, and taking the next identifier is a few instructions.
        private static let nextID = OSAllocatedUnfairLock<UInt64>(initialState: 1)

        /// The association's key: any address unique to this use, and the class object's is.
        private static var key: UnsafeRawPointer {
            UnsafeRawPointer(Unmanaged.passUnretained(LifetimeSentinel.self as AnyObject).toOpaque())
        }
    }
#endif
