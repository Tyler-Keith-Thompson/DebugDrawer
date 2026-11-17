// ViewInspector is linked on Apple platforms only.
#if os(macOS)
    @testable import DebugDrawerNetworkPlugin
    import ViewInspector

    extension Inspection: InspectionEmissary {}
#endif
