#if DEBUG
    import Foundation

    /// A route playback can play: a bundled sample or an imported file.
    struct Route: Identifiable, Codable, Equatable, Sendable {
        let id: String
        /// What the route picker calls it.
        let name: String
        /// Its points, in order, with their offsets, courses and speeds.
        let fixes: [RouteFix]

        /// Seconds from the first point to the last.
        var duration: TimeInterval { fixes.last?.offset ?? 0 }

        /// A route of an imported file, named after it.
        ///
        /// - Parameters:
        ///   - track: The file's points.
        ///   - url: The file, whose name without its extension names the route.
        init(imported track: GPXTrack, from url: URL) {
            let name = url.deletingPathExtension().lastPathComponent
            self.init(id: "imported:\(url.lastPathComponent)", name: name, fixes: track.fixes)
        }

        init(id: String, name: String, fixes: [RouteFix]) {
            self.id = id
            self.name = name
            self.fixes = fixes
        }
    }

    extension Route {
        /// The routes the plugin ships, embedded in its source.
        static let samples: [Route] = [
            sample(named: "Apple Park Loop", gpx: GPXSamples.appleParkLoop),
            sample(named: "Golden Gate Bridge", gpx: GPXSamples.goldenGateBridge)
        ]

        private static func sample(named name: String, gpx: String) -> Route {
            // Can't fire: the samples are fixed text, and a test parses each of them. A sample that
            // didn't parse is a bug in this file, not a condition a caller could handle.
            guard let track = try? GPXTrack(data: Data(gpx.utf8)) else {
                preconditionFailure("The bundled route \(name) isn't valid GPX")
            }
            return Route(id: "sample:\(name)", name: name, fixes: track.fixes)
        }
    }

    extension GPXTrack {
        /// Reads and parses a GPX file the user picked.
        ///
        /// - Parameter url: The file, which may sit outside the app's sandbox.
        /// - Throws: ``GPXError/unreadable`` when it can't be read, or any error of ``init(data:)``.
        init(contentsOf url: URL) throws(GPXError) {
            // A file from the importer is readable only inside its security scope.
            let isScoped = url.startAccessingSecurityScopedResource()
            defer { if isScoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else { throw .unreadable }
            try self.init(data: data)
        }
    }
#endif
