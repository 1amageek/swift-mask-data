public enum IRElement: Hashable, Sendable, Codable {
    case boundary(IRBoundary)
    case path(IRPath)
    case cellRef(IRCellRef)
    case arrayRef(IRArrayRef)
    case text(IRText)
}
