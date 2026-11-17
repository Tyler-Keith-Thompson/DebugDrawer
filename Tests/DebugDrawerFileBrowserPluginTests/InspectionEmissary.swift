// ViewInspector is linked on Apple platforms only.
#if os(macOS)
    @testable import DebugDrawerFileBrowserPlugin
    import ViewInspector

    extension Inspection: InspectionEmissary {}
#endif
