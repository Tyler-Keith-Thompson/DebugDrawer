// ViewInspector is linked on Apple platforms only.
#if os(macOS)
    @testable import DebugDrawerCookiesPlugin
    import ViewInspector

    extension Inspection: InspectionEmissary {}
#endif
