// ViewInspector is linked on Apple platforms only, and the views are tested on the Mac.
#if os(macOS)
    @testable import DebugDrawerConsolePlugin
    @testable import DebugDrawerNetworkPlugin
    import ViewInspector

    extension DebugDrawerNetworkPlugin.Inspection: InspectionEmissary {}
    extension DebugDrawerConsolePlugin.Inspection: InspectionEmissary {}
#endif
