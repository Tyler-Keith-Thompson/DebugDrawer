#if DEBUG
    import Foundation

    // The FileHandle methods DiskIOSwizzler swaps in; each calls itself by its own name, which
    // after the exchange runs the original.
    //
    // A handle doesn't know its path, so each call asks the kernel for it, and records only calls
    // on regular files: a pipe, a socket or a terminal isn't the disk. A failed call isn't
    // recorded, as a closed handle raises when asked for its descriptor, and nothing tells a
    // failed read of a file from one of a pipe without it. The error variants keep the caller's
    // error pointer rather than throwing, so a `nil` result passes through exactly as the
    // original returned it.
    extension FileHandle {
        @objc func dd_writeData(_ data: NSData) {
            guard let call = DiskIOCall.begin() else { return dd_writeData(data) }
            dd_writeData(data)
            let path = regularFilePath
            call.end(path == nil ? nil : .write, path: path ?? "", size: Int64(data.length))
        }

        @objc func dd_writeData(_ data: NSData, error: NSErrorPointer) -> Bool {
            guard let call = DiskIOCall.begin() else { return dd_writeData(data, error: error) }
            let result = dd_writeData(data, error: error)
            let path = result ? regularFilePath : nil
            call.end(path == nil ? nil : .write, path: path ?? "", size: Int64(data.length))
            return result
        }

        @objc func dd_readData(ofLength length: Int) -> NSData {
            guard let call = DiskIOCall.begin() else { return dd_readData(ofLength: length) }
            let result = dd_readData(ofLength: length)
            endRead(call, result)
            return result
        }

        @objc func dd_readDataToEndOfFile() -> NSData {
            guard let call = DiskIOCall.begin() else { return dd_readDataToEndOfFile() }
            let result = dd_readDataToEndOfFile()
            endRead(call, result)
            return result
        }

        @objc func dd_availableData() -> NSData {
            guard let call = DiskIOCall.begin() else { return dd_availableData() }
            let result = dd_availableData()
            endRead(call, result)
            return result
        }

        @objc func dd_readToEndOfFile(error: NSErrorPointer) -> NSData? {
            guard let call = DiskIOCall.begin() else { return dd_readToEndOfFile(error: error) }
            let result = dd_readToEndOfFile(error: error)
            endRead(call, result)
            return result
        }

        @objc func dd_readData(upToLength length: Int, error: NSErrorPointer) -> NSData? {
            guard let call = DiskIOCall.begin() else { return dd_readData(upToLength: length, error: error) }
            let result = dd_readData(upToLength: length, error: error)
            endRead(call, result)
            return result
        }
    }

    extension FileHandle {
        /// Records a read that returned `result`, if it read a regular file.
        fileprivate func endRead(_ call: DiskIOCall, _ result: NSData?) {
            let path = result == nil ? nil : regularFilePath
            call.end(path == nil ? nil : .read, path: path ?? "", size: Int64(result?.length ?? 0))
        }

        /// The path of the regular file the handle has open; `nil` for anything else. Asked only
        /// after a call succeeded, when the handle is open.
        fileprivate var regularFilePath: String? {
            let descriptor = fileDescriptor
            var status = stat()
            guard fstat(descriptor, &status) == 0, status.st_mode & S_IFMT == S_IFREG else { return nil }
            return withUnsafeTemporaryAllocation(of: CChar.self, capacity: Int(MAXPATHLEN)) { buffer in
                guard let base = buffer.baseAddress, fcntl(descriptor, F_GETPATH, base) == 0 else { return nil }
                return String(cString: base)
            }
        }
    }
#endif
