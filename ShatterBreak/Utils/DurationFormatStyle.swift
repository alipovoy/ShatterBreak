import Foundation

struct MinutesSecondsFormatStyle: ParseableFormatStyle {
    var parseStrategy = MinutesSecondsParseStrategy()

    func format(_ value: Double) -> String {
        let maxSeconds = 359999.0 // almost 100 hours, safety bound
        let clampedValue = min(max(value, 0), maxSeconds)
        let totalSeconds = Int(clampedValue)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60

        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct MinutesSecondsParseStrategy: ParseStrategy {
    func parse(_ value: String) throws -> Double {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return 0
        }

        let components = trimmed.split(separator: ":").map { String($0) }

        if components.count == 2 {
            if let minutes = Double(components[0]), let seconds = Double(components[1]) {
                return (minutes * 60) + seconds
            }
        } else if components.count == 1 {
            // Either they type plain seconds "90" or just minutes if we wanted to be smart,
            // but generally plain number is just parsed as seconds, or maybe minutes?
            // "5" might mean 5 minutes if there's no colon, or user may be deleting chars.
            // Let's assume if it's 1-2 digits and no colon, they probably meant seconds,
            // or if we parse as seconds, "90" -> 1:30.
            if let totalSecs = Double(components[0]) {
                return totalSecs
            }
        }

        throw FormatError.invalidFormat
    }

    enum FormatError: Error {
        case invalidFormat
    }
}

extension FormatStyle where Self == MinutesSecondsFormatStyle {
    static var minutesSeconds: MinutesSecondsFormatStyle {
        return MinutesSecondsFormatStyle()
    }
}
