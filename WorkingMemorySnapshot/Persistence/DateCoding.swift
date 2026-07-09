import Foundation

enum DateCoding {
    static func string(from date: Date) -> String {
        formatter.string(from: date)
    }

    static func now() throws -> Date {
        try normalized(Date())
    }

    static func normalized(_ date: Date) throws -> Date {
        try self.date(from: string(from: date))
    }

    static func date(from string: String) throws -> Date {
        guard let date = formatter.date(from: string) else {
            throw DateCodingError.invalidDate(string)
        }

        return date
    }

    private static var formatter: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }
}

enum DateCodingError: Error, Equatable {
    case invalidDate(String)
}
