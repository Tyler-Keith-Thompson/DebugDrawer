#if DEBUG
    import Foundation

    extension DrawerReportResult.State {
        /// Sends `archive` with `uploader`, handing `update` each state it reaches: uploading at
        /// 0, uploading at every fraction the uploader reports, then sent, or upload failed with
        /// the uploader's error. The archive is left on disk either way, so a failure can be retried.
        @MainActor
        static func send(_ archive: URL, with uploader: some DebugDrawerReportUploader, update: (Self) -> Void) async {
            update(.uploading(archive, progress: 0))
            // The uploader reports progress from any thread; a stream brings each fraction to the
            // main actor in order, and it finishes before the outcome is mapped, so a late
            // fraction can't overwrite sent or upload failed.
            let (fractions, continuation) = AsyncStream.makeStream(of: Double.self)
            async let outcome = upload(archive, with: uploader, reportingTo: continuation)
            for await fraction in fractions {
                update(.uploading(archive, progress: min(max(fraction, 0), 1)))
            }
            let result = await outcome
            update(result)
        }

        private static func upload(
            _ archive: URL,
            with uploader: some DebugDrawerReportUploader,
            reportingTo progress: AsyncStream<Double>.Continuation
        ) async -> Self {
            defer { progress.finish() }
            do {
                try await uploader.upload(archive) { progress.yield($0) }
                return .sent(archive)
            } catch {
                return .uploadFailed(archive, reason: error.localizedDescription)
            }
        }
    }
#endif
