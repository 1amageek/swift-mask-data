public struct IRDateTime: Hashable, Sendable, Codable {
    public var year: Int16
    public var month: Int16
    public var day: Int16
    public var hour: Int16
    public var minute: Int16
    public var second: Int16

    public init(year: Int16, month: Int16, day: Int16, hour: Int16, minute: Int16, second: Int16) {
        self.year = year
        self.month = month
        self.day = day
        self.hour = hour
        self.minute = minute
        self.second = second
    }

    public var gdsValues: [Int16] {
        [year, month, day, hour, minute, second]
    }
}
