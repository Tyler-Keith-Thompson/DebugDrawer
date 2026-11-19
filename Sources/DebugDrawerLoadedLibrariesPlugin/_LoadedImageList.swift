#if DEBUG
    import Foundation
    import MachO

    /// dyld's list of the images loaded into this process, each with the UUID from its Mach-O
    /// header and the version of the framework that holds it.
    struct _LoadedImageList: LoadedImageList {
        func images() -> [LoadedImage] {
            (0 ..< _dyld_image_count()).compactMap { index in
                guard let cName = _dyld_get_image_name(index) else { return nil }
                let path = String(cString: cName)
                let header = _dyld_get_image_header(index)
                return LoadedImage(
                    index: index,
                    path: path,
                    uuid: header.flatMap(Self.uuid(of:)),
                    loadAddress: header.map { UInt(bitPattern: $0) } ?? 0,
                    frameworkVersion: Self.frameworkVersion(path: path)
                )
            }
        }

        /// The LC_UUID load command of the Mach-O image whose header is at `header`.
        static func uuid(of header: UnsafePointer<mach_header>) -> UUID? {
            let raw = UnsafeRawPointer(header)
            let headerSize: Int
            switch header.pointee.magic {
            case MH_MAGIC_64: headerSize = MemoryLayout<mach_header_64>.size
            case MH_MAGIC: headerSize = MemoryLayout<mach_header>.size
            default: return nil
            }
            var command = raw + headerSize
            for _ in 0 ..< header.pointee.ncmds {
                let load = command.load(as: load_command.self)
                if load.cmd == UInt32(LC_UUID) {
                    return UUID(uuid: command.load(as: uuid_command.self).uuid)
                }
                command += Int(load.cmdsize)
            }
            return nil
        }

        /// The version in the Info.plist of the `.framework` that contains `path`.
        static func frameworkVersion(path: String) -> String? {
            guard let range = path.range(of: ".framework/", options: .backwards) else { return nil }
            let frameworkPath = String(path[..<range.lowerBound]) + ".framework"
            return Bundle(path: frameworkPath)?.infoDictionary?["CFBundleShortVersionString"] as? String
        }
    }
#endif
