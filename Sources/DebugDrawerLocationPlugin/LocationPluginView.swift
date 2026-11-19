#if DEBUG
    import DebugDrawer
    import SwiftUI
    import UniformTypeIdentifiers

    /// Draws the Location Simulator from its model's snapshot, through a transport, and sends it
    /// what the user does; `LocationForm` and `RouteSection` draw the values. It presents the file
    /// importer for Import GPX….
    struct LocationPluginView: View {
        @StateObject private var transport: DebugDrawerPluginTransport<LocationSnapshot, LocationCommand>
        @State private var isImporting = false

        /// - Parameter transport: Joins the view to the model; the plugin passes
        ///   `.direct(to: model)`.
        init(transport: @escaping @autoclosure () -> DebugDrawerPluginTransport<LocationSnapshot, LocationCommand>) {
            _transport = StateObject(wrappedValue: transport())
        }

        var body: some View {
            let snapshot = transport.snapshot
            VStack(alignment: .leading, spacing: 0) {
                LocationForm(
                    isEnabled: Binding(get: { transport.snapshot.isEnabled }, set: { send(.setEnabled($0)) }),
                    latitudeText: Binding(get: { transport.snapshot.latitudeText }, set: { send(.setLatitudeText($0)) }),
                    longitudeText: Binding(get: { transport.snapshot.longitudeText }, set: { send(.setLongitudeText($0)) }),
                    active: snapshot.active,
                    presets: snapshot.presets
                ) { send(.choosePreset($0)) }
                if snapshot.isEnabled {
                    RouteSection(
                        routes: snapshot.routes,
                        selection: Binding(get: { transport.snapshot.routeID }, set: { send(.selectRoute($0)) }),
                        speed: Binding(get: { transport.snapshot.speed }, set: { send(.setSpeed($0)) }),
                        playback: snapshot.playback,
                        importFailure: snapshot.importFailure,
                        actions: RouteActions(
                            play: { send(.play) },
                            pause: { send(.pause) },
                            stop: { send(.stop) },
                            importFile: { isImporting = true }
                        )
                    )
                }
            }
            .fileImporter(isPresented: $isImporting, allowedContentTypes: [.gpx, .xml]) { result in
                if case let .success(url) = result {
                    send(.importRoute(url))
                }
            }
        }

        private func send(_ action: LocationCommand.Action) {
            transport.send(LocationCommand(action))
        }
    }

    extension UTType {
        /// GPX files, by their extension: the system declares no type for them.
        fileprivate static let gpx = UTType(filenameExtension: "gpx", conformingTo: .xml) ?? .xml
    }
#endif
