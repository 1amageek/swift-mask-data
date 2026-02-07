/// Options for controlling GDSII reading behavior.
public struct GDSReadOptions: Sendable {
    /// How to handle BOX records.
    public enum BOXMode: Sendable {
        /// Convert BOX to IRBoundary (default, matches KLayout "as rectangles").
        case asBoundary
        /// Skip BOX records entirely.
        case ignore
    }

    public var boxMode: BOXMode

    public init(boxMode: BOXMode = .asBoundary) {
        self.boxMode = boxMode
    }

    public static let `default` = GDSReadOptions()
}
