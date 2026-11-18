#if DEBUG
    import Foundation

    // The FileManager methods DiskIOSwizzler swaps in; each calls itself by its own name, which
    // after the exchange runs the original.
    extension FileManager {
        @objc func dd_contents(atPath path: String) -> NSData? {
            guard let call = DiskIOCall.begin() else { return dd_contents(atPath: path) }
            let result = dd_contents(atPath: path)
            call.end(
                .read, path: path, size: Int64(result?.length ?? 0),
                error: result == nil ? DiskIOCall.lastError(else: .fileReadUnknown) : nil
            )
            return result
        }

        @objc func dd_createFile(atPath path: String, contents data: NSData?, attributes: NSDictionary?) -> Bool {
            guard let call = DiskIOCall.begin() else { return dd_createFile(atPath: path, contents: data, attributes: attributes) }
            let result = dd_createFile(atPath: path, contents: data, attributes: attributes)
            call.end(
                .create, path: path, size: Int64(data?.length ?? 0),
                error: result ? nil : DiskIOCall.lastError(else: .fileWriteUnknown)
            )
            return result
        }

        @objc func dd_createDirectory(atPath path: String, withIntermediateDirectories: Bool, attributes: NSDictionary?) throws {
            guard let call = DiskIOCall.begin() else {
                return try dd_createDirectory(atPath: path, withIntermediateDirectories: withIntermediateDirectories, attributes: attributes)
            }
            do {
                try dd_createDirectory(atPath: path, withIntermediateDirectories: withIntermediateDirectories, attributes: attributes)
                call.end(.create, path: path)
            } catch {
                call.end(.create, path: path, error: error)
                throw error
            }
        }

        @objc func dd_createDirectory(at url: URL, withIntermediateDirectories: Bool, attributes: NSDictionary?) throws {
            guard let call = DiskIOCall.begin() else {
                return try dd_createDirectory(at: url, withIntermediateDirectories: withIntermediateDirectories, attributes: attributes)
            }
            do {
                try dd_createDirectory(at: url, withIntermediateDirectories: withIntermediateDirectories, attributes: attributes)
                call.end(.create, path: url.path(percentEncoded: false))
            } catch {
                call.end(.create, path: url.path(percentEncoded: false), error: error)
                throw error
            }
        }

        @objc func dd_removeItem(atPath path: String) throws {
            guard let call = DiskIOCall.begin() else { return try dd_removeItem(atPath: path) }
            do {
                try dd_removeItem(atPath: path)
                call.end(.delete, path: path)
            } catch {
                call.end(.delete, path: path, error: error)
                throw error
            }
        }

        @objc func dd_removeItem(at url: URL) throws {
            guard let call = DiskIOCall.begin() else { return try dd_removeItem(at: url) }
            do {
                try dd_removeItem(at: url)
                call.end(.delete, path: url.path(percentEncoded: false))
            } catch {
                call.end(.delete, path: url.path(percentEncoded: false), error: error)
                throw error
            }
        }

        @objc func dd_contentsOfDirectory(atPath path: String) throws -> NSArray {
            guard let call = DiskIOCall.begin() else { return try dd_contentsOfDirectory(atPath: path) }
            do {
                let result = try dd_contentsOfDirectory(atPath: path)
                call.end(.list, path: path, size: Int64(result.count))
                return result
            } catch {
                call.end(.list, path: path, error: error)
                throw error
            }
        }

        @objc func dd_contentsOfDirectory(
            at url: URL, includingPropertiesForKeys keys: NSArray?, options: FileManager.DirectoryEnumerationOptions
        ) throws -> NSArray {
            guard let call = DiskIOCall.begin() else {
                return try dd_contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: options)
            }
            do {
                let result = try dd_contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: options)
                call.end(.list, path: url.path(percentEncoded: false), size: Int64(result.count))
                return result
            } catch {
                call.end(.list, path: url.path(percentEncoded: false), error: error)
                throw error
            }
        }

        @objc func dd_attributesOfItem(atPath path: String) throws -> NSDictionary {
            guard let call = DiskIOCall.begin() else { return try dd_attributesOfItem(atPath: path) }
            do {
                let result = try dd_attributesOfItem(atPath: path)
                call.end(.stat, path: path, size: (result[FileAttributeKey.size] as? NSNumber)?.int64Value ?? 0)
                return result
            } catch {
                call.end(.stat, path: path, error: error)
                throw error
            }
        }

        @objc func dd_copyItem(atPath source: String, toPath destination: String) throws {
            guard let call = DiskIOCall.begin() else { return try dd_copyItem(atPath: source, toPath: destination) }
            do {
                try dd_copyItem(atPath: source, toPath: destination)
                call.end(.copy, path: source, destination: destination)
            } catch {
                call.end(.copy, path: source, destination: destination, error: error)
                throw error
            }
        }

        @objc func dd_copyItem(at source: URL, to destination: URL) throws {
            guard let call = DiskIOCall.begin() else { return try dd_copyItem(at: source, to: destination) }
            do {
                try dd_copyItem(at: source, to: destination)
                call.end(.copy, path: source.path(percentEncoded: false), destination: destination.path(percentEncoded: false))
            } catch {
                call.end(.copy, path: source.path(percentEncoded: false), destination: destination.path(percentEncoded: false), error: error)
                throw error
            }
        }

        @objc func dd_moveItem(atPath source: String, toPath destination: String) throws {
            guard let call = DiskIOCall.begin() else { return try dd_moveItem(atPath: source, toPath: destination) }
            do {
                try dd_moveItem(atPath: source, toPath: destination)
                call.end(.move, path: source, destination: destination)
            } catch {
                call.end(.move, path: source, destination: destination, error: error)
                throw error
            }
        }

        @objc func dd_moveItem(at source: URL, to destination: URL) throws {
            guard let call = DiskIOCall.begin() else { return try dd_moveItem(at: source, to: destination) }
            do {
                try dd_moveItem(at: source, to: destination)
                call.end(.move, path: source.path(percentEncoded: false), destination: destination.path(percentEncoded: false))
            } catch {
                call.end(.move, path: source.path(percentEncoded: false), destination: destination.path(percentEncoded: false), error: error)
                throw error
            }
        }
    }
#endif
