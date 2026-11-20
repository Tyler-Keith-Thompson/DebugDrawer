import Foundation
import MachO

// What a captured address can be named by in a production build. `dladdr` names only what an image
// exports: an App Store build is stripped, so the app's own frames come back as the nearest exported
// symbol or none, while the system's libraries keep their names. So each frame also carries its
// image's file name, LC_UUID and the address's offset into the image, which is what `atos` or any
// symbolicator needs to name the frame from the build's dSYM, and which no stripping removes.
// Rejected: symbolicating in the app with a dSYM (a production app ships none) and reading the
// symbol table by hand (stripped too).

/// Names captured addresses with `dladdr`, after the sampled thread runs again: `dladdr` takes
/// dyld's lock, which a stopped thread could hold.
package enum Symbolicator {
    /// Each address's frame, innermost first: its image, the image's UUID, the offset into it, and
    /// the nearest exported symbol with the offset into that.
    ///
    /// Every address after the first is a return address, just past its call, which may be the
    /// last instruction of a function; its symbol is looked up one byte earlier, so it names the
    /// caller. The image offset is of the address itself, as crash reports give it.
    ///
    /// - Complexity: O(*n*) in the addresses, each a `dladdr` lookup and a walk of its image's
    ///   load commands.
    package static func frames(for addresses: [UInt]) -> [PerformanceTraces.Frame] {
        addresses.enumerated().map { index, address in
            frame(address: address, lookup: index == 0 ? address : address &- 1)
        }
    }

    /// One line per address, as `backtrace_symbols(3)` writes them: its index, the image's file
    /// name, the address, and the nearest symbol with the offset into it.
    ///
    /// Symbols stay mangled, as Copy Report copies them; the drawer demangles them as it draws the
    /// frames. A symbol the image doesn't export is named by the nearest one it does, or `???`.
    package static func lines(for addresses: [UInt]) -> [String] {
        frames(for: addresses).enumerated().map { index, frame in frame.line(index: index) }
    }

    private static func frame(address: UInt, lookup: UInt) -> PerformanceTraces.Frame {
        var info = Dl_info()
        guard let pointer = UnsafeRawPointer(bitPattern: lookup), dladdr(pointer, &info) != 0 else {
            return PerformanceTraces.Frame(address: UInt64(address))
        }
        let image = info.dli_fname.map { String(cString: $0) }.map { path in
            path.split(separator: "/").last.map(String.init) ?? path
        }
        let base = info.dli_fbase.map { UInt(bitPattern: $0) }
        let symbolStart = info.dli_saddr.map { UInt(bitPattern: $0) }
        return PerformanceTraces.Frame(
            address: UInt64(address),
            image: image,
            imageUUID: info.dli_fbase.flatMap(Self.uuid(ofImageAt:)),
            imageOffset: base.map { UInt64(address &- $0) },
            symbol: info.dli_sname.map { String(cString: $0) },
            symbolOffset: symbolStart.map { UInt64(address &- $0) }
        )
    }

    /// The UUID in the LC_UUID load command of the 64-bit Mach-O image whose header is at
    /// `header`, or `nil` when it has none.
    private static func uuid(ofImageAt header: UnsafeMutableRawPointer) -> UUID? {
        let machHeader = header.assumingMemoryBound(to: mach_header_64.self).pointee
        guard machHeader.magic == MH_MAGIC_64 else { return nil }
        var command = UnsafeRawPointer(header) + MemoryLayout<mach_header_64>.size
        for _ in 0 ..< machHeader.ncmds {
            let load = command.loadUnaligned(as: load_command.self)
            if load.cmd == UInt32(LC_UUID) {
                return UUID(uuid: command.loadUnaligned(as: uuid_command.self).uuid)
            }
            command += Int(load.cmdsize)
        }
        return nil
    }
}

extension PerformanceTraces.Frame {
    /// The frame as `backtrace_symbols(3)` writes it, at `index`.
    package func line(index: Int) -> String {
        let hex = String(format: "0x%016llx", address)
        guard let image else { return "\(index) ??? \(hex)" }
        guard let symbol, let symbolOffset else { return "\(index) \(image) \(hex)" }
        return "\(index) \(image) \(hex) \(symbol) + \(symbolOffset)"
    }
}
