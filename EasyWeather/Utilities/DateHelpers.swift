import Foundation

enum DateHelpers {
    static func calendar(for timezoneIdentifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timezoneIdentifier) ?? .current
        return calendar
    }

    static func dayAnchors(timezoneIdentifier: String, now: Date = Date()) -> (yesterday: Date, today: Date, tomorrow: Date) {
        let calendar = calendar(for: timezoneIdentifier)
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        return (yesterday, today, tomorrow)
    }

    static func matchingDay(
        in days: [DailyWeather],
        targetDay: Date,
        timezoneIdentifier: String
    ) -> DailyWeather? {
        let calendar = calendar(for: timezoneIdentifier)
        return days.first(where: { calendar.isDate($0.date, inSameDayAs: targetDay) })
    }
}
