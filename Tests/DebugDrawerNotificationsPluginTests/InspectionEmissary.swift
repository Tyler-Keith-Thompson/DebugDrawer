// ViewInspector is linked on Apple platforms only.
#if os(macOS)
    @testable import DebugDrawerNotificationsPlugin
    import ViewInspector

    extension Inspection: InspectionEmissary {}
#endif
