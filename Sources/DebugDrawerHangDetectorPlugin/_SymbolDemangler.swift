#if DEBUG
    import Darwin

    /// The Swift runtime's own demangler, `swift_demangle`, which libswiftCore exports but no SDK
    /// header declares, found with `dlsym` the first time a frame is named.
    ///
    /// It allocates, so it runs only when the drawer draws a hang, never while the main thread is stopped.
    struct _SymbolDemangler: SymbolDemangler {
        func demangle(_ symbol: String) -> String? {
            guard let swiftDemangle = Self.swiftDemangle else { return nil }
            return symbol.withCString { name in
                // With no buffer passed in, it returns one it allocated with malloc, or nil for a
                // name that isn't a mangled Swift symbol (C, Objective-C).
                guard let buffer = swiftDemangle(name, strlen(name), nil, nil, 0) else { return nil }
                defer { free(buffer) }
                return String(cString: buffer)
            }
        }

        /// `char *swift_demangle(const char *mangledName, size_t mangledNameLength, char
        /// *outputBuffer, size_t *outputBufferSize, uint32_t flags)`.
        private typealias SwiftDemangle = @convention(c) (
            UnsafePointer<CChar>?, Int, UnsafeMutablePointer<CChar>?, UnsafeMutablePointer<Int>?, UInt32
        ) -> UnsafeMutablePointer<CChar>?

        private static let swiftDemangle: SwiftDemangle? = {
            // RTLD_DEFAULT, which Swift doesn't import: search every image loaded.
            let everyImage = UnsafeMutableRawPointer(bitPattern: -2)
            return dlsym(everyImage, "swift_demangle").map { unsafeBitCast($0, to: SwiftDemangle.self) }
        }()
    }
#endif
