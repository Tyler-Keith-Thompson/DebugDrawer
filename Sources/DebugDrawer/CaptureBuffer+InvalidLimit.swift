public extension CaptureBuffer {
    /// A bound a capture buffer can't take.
    enum InvalidLimit: Error, Equatable, Sendable {
        /// The most elements kept is negative.
        case negativeMaxCount
        /// The most the kept elements' byte costs add up to is negative.
        case negativeMaxByteCount
    }
}
