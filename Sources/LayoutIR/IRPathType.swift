public enum IRPathType: Int16, Hashable, Sendable, Codable {
    /// Square flush ends (GDSII pathtype 0).
    case flush = 0
    /// Round ends (GDSII pathtype 1).
    case round = 1
    /// Square half-width extension (GDSII pathtype 2).
    case halfWidthExtend = 2
    /// Custom extension with explicit begin/end values (GDSII pathtype 4).
    case customExtension = 4
}
