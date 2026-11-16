#if DEBUG
    import Foundation

    /// Names captured addresses with `dladdr`, after the sampled thread runs again: `dladdr`
    /// takes dyld's lock, which a stopped thread could hold.
    enum Symbolicator {
        /// One line per address, as `backtrace_symbols(3)` writes them: its index, the image's
        /// file name, the address, and the nearest symbol with the offset into it.
        ///
        /// Every address after the first is a return address, just past its call, which may be
        /// the last instruction of a function; it is looked up one byte earlier, so it names the
        /// caller. Symbols stay mangled; a symbol the image doesn't export is named by the nearest
        /// one it does, or `???`.
        static func lines(for addresses: [UInt]) -> [String] {
            addresses.enumerated().map { index, address in
                line(index: index, address: address, lookup: index == 0 ? address : address &- 1)
            }
        }

        private static func line(index: Int, address: UInt, lookup: UInt) -> String {
            let hex = String(format: "0x%016lx", address)
            var info = Dl_info()
            guard let pointer = UnsafeRawPointer(bitPattern: lookup), dladdr(pointer, &info) != 0 else {
                return "\(index) ??? \(hex)"
            }
            let image = info.dli_fname.map { String(cString: $0) }.map { $0.split(separator: "/").last.map(String.init) ?? $0 } ?? "???"
            guard let name = info.dli_sname, let start = info.dli_saddr else {
                return "\(index) \(image) \(hex)"
            }
            return "\(index) \(image) \(hex) \(String(cString: name)) + \(address &- UInt(bitPattern: start))"
        }
    }
#endif
