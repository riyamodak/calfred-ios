import Foundation

public enum DomainError: Error, LocalizedError, Equatable {
    case invalidDate
    case invalidTimeRange
    case invalidTimeZone
    case invalidField(String)

    public var errorDescription: String? {
        switch self {
        case .invalidDate: return "This event contains an invalid date."
        case .invalidTimeRange: return "The event must end after it starts."
        case .invalidTimeZone: return "This event contains an unsupported time zone."
        case .invalidField(let name): return "This event contains an invalid \(name)."
        }
    }
}

/// A calendar date, never an instant. All-day ends are exclusive.
public struct LocalDate: Codable, Hashable, Sendable, Comparable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) throws {
        let leap = year.isMultiple(of: 400) || (year.isMultiple(of: 4) && !year.isMultiple(of: 100))
        let lengths = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        guard (1...9999).contains(year), (1...12).contains(month),
              (1...lengths[month - 1]).contains(day) else { throw DomainError.invalidDate }
        self.year = year
        self.month = month
        self.day = day
    }

    public init(_ string: String) throws {
        let bytes = Array(string.utf8)
        guard bytes.count == 10, bytes[4] == 45, bytes[7] == 45,
              bytes.enumerated().allSatisfy({ [4, 7].contains($0.offset) || (48...57).contains($0.element) }),
              let year = Int(string.prefix(4)), let month = Int(string.dropFirst(5).prefix(2)),
              let day = Int(string.suffix(2)) else { throw DomainError.invalidDate }
        try self.init(year: year, month: month, day: day)
    }

    public var description: String { String(format: "%04d-%02d-%02d", year, month, day) }

    public static func < (lhs: LocalDate, rhs: LocalDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    public func date(in timeZone: TimeZone) throws -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else {
            throw DomainError.invalidDate
        }
        // A skipped local date (for example a historical date-line transition) cannot be represented.
        guard Self.from(date, in: timeZone) == self else { throw DomainError.invalidDate }
        return date
    }

    public static func from(_ date: Date, in timeZone: TimeZone) -> LocalDate {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        // The calendar supplies valid Gregorian components for supported event dates.
        return LocalDate(uncheckedYear: components.year ?? 1, month: components.month ?? 1, day: components.day ?? 1)
    }

    private init(uncheckedYear year: Int, month: Int, day: Int) {
        self.year = year; self.month = month; self.day = day
    }

    public init(from decoder: Decoder) throws {
        try self.init(decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

/// Strict RFC3339 input for transport; the wire output uses millisecond precision.
public enum EventTimestamp {
    public static func parse(_ string: String) throws -> Date {
        let pattern = #"^\d{4}-\d{2}-\d{2}T([0-1]\d|2[0-3]):[0-5]\d:[0-5]\d(?:\.\d{1,9})?(?:Z|[+-](?:[0-1]\d|2[0-3]):[0-5]\d)$"#
        guard string.range(of: pattern, options: .regularExpression) != nil else { throw DomainError.invalidDate }
        _ = try LocalDate(String(string.prefix(10)))
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = string.contains(".") ? [.withInternetDateTime, .withFractionalSeconds] : [.withInternetDateTime]
        guard let date = formatter.date(from: string), date.timeIntervalSince1970.isFinite else { throw DomainError.invalidDate }
        return date
    }

    public static func string(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }
}
