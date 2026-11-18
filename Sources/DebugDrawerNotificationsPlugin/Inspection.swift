#if DEBUG
    // ViewInspector's hook for views with their own state:
    // https://github.com/nalexn/ViewInspector/blob/0.10.6/guide.md#approach-2
    // A view holds one and forwards `notice` to `visit`; the test target conforms it to
    // `InspectionEmissary`, so the library itself never links ViewInspector. A copy of core's,
    // which is internal to core: a dozen lines cost less than making it part of the plugin
    // contract.
    import Combine

    final class Inspection<V>: @unchecked Sendable {
        let notice = PassthroughSubject<UInt, Never>()
        var callbacks = [UInt: (V) -> Void]()

        func visit(_ view: V, _ line: UInt) {
            if let callback = callbacks.removeValue(forKey: line) {
                callback(view)
            }
        }
    }
#endif
