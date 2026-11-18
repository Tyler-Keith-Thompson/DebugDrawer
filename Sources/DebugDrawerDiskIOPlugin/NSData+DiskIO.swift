#if DEBUG
    import Foundation

    // The NSData methods DiskIOSwizzler swaps in; each calls itself by its own name, which
    // after the exchange runs the original.
    extension NSData {
        @objc func dd_write(toFile path: String, atomically: Bool) -> Bool {
            guard let call = DiskIOCall.begin() else { return dd_write(toFile: path, atomically: atomically) }
            let result = dd_write(toFile: path, atomically: atomically)
            call.end(.write, path: path, size: Int64(length), error: result ? nil : DiskIOCall.lastError(else: .fileWriteUnknown))
            return result
        }

        @objc func dd_write(to url: URL, atomically: Bool) -> Bool {
            guard let call = DiskIOCall.begin() else { return dd_write(to: url, atomically: atomically) }
            let result = dd_write(to: url, atomically: atomically)
            call.end(
                url.isFileURL ? .write : nil, path: url.path(percentEncoded: false), size: Int64(length),
                error: result ? nil : DiskIOCall.lastError(else: .fileWriteUnknown)
            )
            return result
        }

        @objc func dd_write(toFile path: String, options: NSData.WritingOptions) throws {
            guard let call = DiskIOCall.begin() else { return try dd_write(toFile: path, options: options) }
            do {
                try dd_write(toFile: path, options: options)
                call.end(.write, path: path, size: Int64(length))
            } catch {
                call.end(.write, path: path, error: error)
                throw error
            }
        }

        @objc func dd_write(to url: URL, options: NSData.WritingOptions) throws {
            guard let call = DiskIOCall.begin() else { return try dd_write(to: url, options: options) }
            let operation: IOEvent.Operation? = url.isFileURL ? .write : nil
            do {
                try dd_write(to: url, options: options)
                call.end(operation, path: url.path(percentEncoded: false), size: Int64(length))
            } catch {
                call.end(operation, path: url.path(percentEncoded: false), error: error)
                throw error
            }
        }
    }
#endif
