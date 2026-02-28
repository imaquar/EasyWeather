import CoreLocation
import SwiftUI
import WidgetKit

private enum WidgetStorage {
    static let kind = "EasyWeatherTodayWidget"
    static let appGroupID = "group.aquariusss.easyweather"
    static let snapshotKey = "easyweather.widget.today.snapshot"
}

private struct WeatherWidgetSnapshot: Codable {
    let city: String
    let line1: String
    let line2: String
    let line3: String
    let temperatureText: String
    let iconName: String
    let periods: [WidgetPeriodSnapshot]
    let updatedAt: Date

    private enum CodingKeys: String, CodingKey {
        case city
        case line1
        case line2
        case line3
        case temperatureText
        case iconName
        case periods
        case updatedAt
    }

    init(
        city: String,
        line1: String,
        line2: String,
        line3: String,
        temperatureText: String,
        iconName: String,
        periods: [WidgetPeriodSnapshot] = [],
        updatedAt: Date
    ) {
        self.city = city
        self.line1 = line1
        self.line2 = line2
        self.line3 = line3
        self.temperatureText = temperatureText
        self.iconName = iconName
        self.periods = periods
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        city = try container.decode(String.self, forKey: .city)
        line1 = try container.decode(String.self, forKey: .line1)
        line2 = try container.decode(String.self, forKey: .line2)
        line3 = try container.decode(String.self, forKey: .line3)
        temperatureText = try container.decode(String.self, forKey: .temperatureText)
        iconName = try container.decode(String.self, forKey: .iconName)
        periods = try container.decodeIfPresent([WidgetPeriodSnapshot].self, forKey: .periods) ?? []
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}

private struct WidgetPeriodSnapshot: Codable, Identifiable {
    let label: String
    let temperatureText: String
    let iconName: String

    var id: String { label }
}

private struct WeatherWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WeatherWidgetSnapshot?
}

private struct WeatherWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> WeatherWidgetEntry {
        WeatherWidgetEntry(date: Date(), snapshot: sampleSnapshot)
    }

    func getSnapshot(in context: Context, completion: @escaping (WeatherWidgetEntry) -> Void) {
        completion(WeatherWidgetEntry(date: Date(), snapshot: loadSnapshot() ?? sampleSnapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WeatherWidgetEntry>) -> Void) {
        Task {
            let fallback = loadSnapshot() ?? sampleSnapshot
            let fresh = await loadFreshSnapshot(fallback: fallback)
            let snapshot = fresh ?? fallback

            if let fresh {
                saveSnapshot(fresh)
            }

            let entry = WeatherWidgetEntry(date: Date(), snapshot: snapshot)
            let nextUpdate = Date().addingTimeInterval(30 * 60)
            completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
        }
    }

    private var sampleSnapshot: WeatherWidgetSnapshot {
        WeatherWidgetSnapshot(
            city: "Current Location",
            line1: "today is",
            line2: "SIMILAR",
            line3: "as yesterday",
            temperatureText: "--°C",
            iconName: "cloud",
            updatedAt: Date()
        )
    }

    private func loadSnapshot() -> WeatherWidgetSnapshot? {
        let defaults = UserDefaults(suiteName: WidgetStorage.appGroupID) ?? .standard
        guard let data = defaults.data(forKey: WidgetStorage.snapshotKey) else {
            return nil
        }

        return try? JSONDecoder().decode(WeatherWidgetSnapshot.self, from: data)
    }

    private func saveSnapshot(_ snapshot: WeatherWidgetSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else {
            return
        }

        let defaults = UserDefaults(suiteName: WidgetStorage.appGroupID) ?? .standard
        defaults.set(data, forKey: WidgetStorage.snapshotKey)
    }

    private func loadFreshSnapshot(fallback: WeatherWidgetSnapshot) async -> WeatherWidgetSnapshot? {
        guard let coordinate = await requestWidgetCoordinate() else {
            return nil
        }

        return try? await fetchOpenMeteoSnapshot(for: coordinate, fallbackCity: fallback.city)
    }

    @MainActor
    private func requestWidgetCoordinate() async -> CLLocationCoordinate2D? {
        guard CLLocationManager.locationServicesEnabled() else {
            return nil
        }

        let manager = CLLocationManager()
        guard manager.isAuthorizedForWidgetUpdates else {
            return nil
        }

        let requester = WidgetLocationRequester()
        return await requester.requestLocation(using: manager)
    }

    private func fetchOpenMeteoSnapshot(
        for coordinate: CLLocationCoordinate2D,
        fallbackCity: String
    ) async throws -> WeatherWidgetSnapshot {
        guard let url = buildOpenMeteoURL(for: coordinate) else {
            return sampleSnapshot
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            return sampleSnapshot
        }

        let decoded = try JSONDecoder().decode(OpenMeteoWidgetResponse.self, from: data)
        let timezone = TimeZone(identifier: decoded.timezone) ?? .current
        let calendar = widgetCalendar(timezone: timezone)

        guard
            let today = findDay(offset: 0, in: decoded.daily, calendar: calendar, timezone: timezone),
            let yesterday = findDay(offset: -1, in: decoded.daily, calendar: calendar, timezone: timezone)
        else {
            return sampleSnapshot
        }

        let todayComparison = roundOneDecimal((today.high + today.low) / 2)
        let yesterdayComparison = roundOneDecimal((yesterday.high + yesterday.low) / 2)
        let delta = todayComparison - yesterdayComparison

        let relation: String
        let line3: String
        if abs(delta) < 0.5 {
            relation = "SIMILAR"
            line3 = "as yesterday"
        } else if delta >= 0.5 {
            relation = "WARMER"
            line3 = "than yesterday"
        } else {
            relation = "COLDER"
            line3 = "than yesterday"
        }

        let periodSnapshots = buildPeriodSnapshots(
            for: today.date,
            hourly: decoded.hourly,
            calendar: calendar,
            timezone: timezone,
            fallbackHigh: today.high,
            fallbackLow: today.low,
            fallbackCode: today.weatherCode
        )

        return WeatherWidgetSnapshot(
            city: fallbackCity,
            line1: "today is",
            line2: relation,
            line3: line3,
            temperatureText: "\(Int(todayComparison.rounded()))°C",
            iconName: symbolName(for: today.weatherCode),
            periods: periodSnapshots,
            updatedAt: Date()
        )
    }

    private func buildOpenMeteoURL(for coordinate: CLLocationCoordinate2D) -> URL? {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(coordinate.latitude)),
            URLQueryItem(name: "longitude", value: String(coordinate.longitude)),
            URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min,weather_code"),
            URLQueryItem(name: "hourly", value: "temperature_2m,weather_code"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "temperature_unit", value: "celsius"),
            URLQueryItem(name: "past_days", value: "2"),
            URLQueryItem(name: "forecast_days", value: "3")
        ]
        return components?.url
    }

    private func widgetCalendar(timezone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone
        return calendar
    }

    private func findDay(
        offset: Int,
        in daily: OpenMeteoWidgetResponse.Daily,
        calendar: Calendar,
        timezone: TimeZone
    ) -> (date: Date, high: Double, low: Double, weatherCode: Int)? {
        let count = min(daily.time.count, daily.temperatureMax.count, daily.temperatureMin.count, daily.weatherCode.count)
        guard count > 0 else { return nil }

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timezone
        formatter.dateFormat = "yyyy-MM-dd"

        let targetDay = calendar.startOfDay(for: calendar.date(byAdding: .day, value: offset, to: Date()) ?? Date())

        for index in 0..<count {
            guard let date = formatter.date(from: daily.time[index]) else {
                continue
            }

            if calendar.isDate(date, inSameDayAs: targetDay) {
                return (date, daily.temperatureMax[index], daily.temperatureMin[index], daily.weatherCode[index])
            }
        }

        return nil
    }

    private func buildPeriodSnapshots(
        for dayDate: Date,
        hourly: OpenMeteoWidgetResponse.Hourly,
        calendar: Calendar,
        timezone: TimeZone,
        fallbackHigh: Double,
        fallbackLow: Double,
        fallbackCode: Int
    ) -> [WidgetPeriodSnapshot] {
        let hourPairs: [(String, Int)] = [("morning", 8), ("noon", 12), ("evening", 18), ("night", 22)]
        let dayStart = calendar.startOfDay(for: dayDate)
        let hourlyItems = parseHourly(hourly, calendar: calendar, timezone: timezone)
            .filter { calendar.isDate($0.date, inSameDayAs: dayStart) }

        return hourPairs.map { label, hour in
            let target = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: dayStart) ?? dayStart
            if let nearest = nearestHourly(to: target, in: hourlyItems) {
                return WidgetPeriodSnapshot(
                    label: label,
                    temperatureText: "\(Int(nearest.temperature.rounded()))°C",
                    iconName: symbolName(for: nearest.weatherCode)
                )
            }

            let fallbackTemp = fallbackTemperature(
                for: label,
                high: fallbackHigh,
                low: fallbackLow
            )
            return WidgetPeriodSnapshot(
                label: label,
                temperatureText: "\(Int(fallbackTemp.rounded()))°C",
                iconName: symbolName(for: fallbackCode)
            )
        }
    }

    private func parseHourly(
        _ hourly: OpenMeteoWidgetResponse.Hourly,
        calendar: Calendar,
        timezone: TimeZone
    ) -> [(date: Date, temperature: Double, weatherCode: Int)] {
        let count = min(hourly.time.count, hourly.temperature.count, hourly.weatherCode.count)
        guard count > 0 else { return [] }

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timezone
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"

        var result: [(date: Date, temperature: Double, weatherCode: Int)] = []
        result.reserveCapacity(count)

        for index in 0..<count {
            guard let date = formatter.date(from: hourly.time[index]) else {
                continue
            }

            result.append((date, hourly.temperature[index], hourly.weatherCode[index]))
        }

        return result
    }

    private func nearestHourly(
        to targetDate: Date,
        in items: [(date: Date, temperature: Double, weatherCode: Int)]
    ) -> (date: Date, temperature: Double, weatherCode: Int)? {
        items.min { left, right in
            abs(left.date.timeIntervalSince(targetDate)) < abs(right.date.timeIntervalSince(targetDate))
        }
    }

    private func fallbackTemperature(for label: String, high: Double, low: Double) -> Double {
        let range = high - low
        switch label {
        case "morning":
            return low + range * 0.25
        case "noon":
            return low + range * 0.85
        case "evening":
            return low + range * 0.55
        case "night":
            return low + range * 0.15
        default:
            return (high + low) / 2
        }
    }

    private func roundOneDecimal(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }

    private func symbolName(for weatherCode: Int) -> String {
        switch weatherCode {
        case 0:
            return "sun.max.fill"
        case 1, 2:
            return "cloud.sun.fill"
        case 3:
            return "cloud.fill"
        case 45, 48:
            return "cloud.fog.fill"
        case 51, 53, 55:
            return "cloud.drizzle.fill"
        case 56, 57, 66, 67:
            return "cloud.sleet.fill"
        case 61, 63, 65:
            return "cloud.rain.fill"
        case 71, 73, 75, 77, 85, 86:
            return "cloud.snow.fill"
        case 80, 81, 82:
            return "cloud.heavyrain.fill"
        case 95, 96, 99:
            return "cloud.bolt.rain.fill"
        default:
            return "cloud.fill"
        }
    }
}

private final class WidgetLocationRequester: NSObject, CLLocationManagerDelegate {
    private var continuation: CheckedContinuation<CLLocationCoordinate2D?, Never>?
    private weak var manager: CLLocationManager?

    @MainActor
    func requestLocation(using manager: CLLocationManager) async -> CLLocationCoordinate2D? {
        self.manager = manager
        manager.delegate = self

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            manager.requestLocation()

            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
                self?.finish(with: nil)
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        finish(with: locations.first?.coordinate)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        finish(with: nil)
    }

    private func finish(with coordinate: CLLocationCoordinate2D?) {
        guard let continuation else {
            return
        }

        manager?.delegate = nil
        self.continuation = nil
        continuation.resume(returning: coordinate)
    }
}

private struct OpenMeteoWidgetResponse: Decodable {
    let timezone: String
    let daily: Daily
    let hourly: Hourly

    struct Daily: Decodable {
        let time: [String]
        let temperatureMax: [Double]
        let temperatureMin: [Double]
        let weatherCode: [Int]

        private enum CodingKeys: String, CodingKey {
            case time
            case temperatureMax = "temperature_2m_max"
            case temperatureMin = "temperature_2m_min"
            case weatherCode = "weather_code"
        }
    }

    struct Hourly: Decodable {
        let time: [String]
        let temperature: [Double]
        let weatherCode: [Int]

        private enum CodingKeys: String, CodingKey {
            case time
            case temperature = "temperature_2m"
            case weatherCode = "weather_code"
        }
    }
}

private struct EasyWeatherTodayWidgetView: View {
    var entry: WeatherWidgetEntry

    @Environment(\.widgetFamily) private var widgetFamily

    var body: some View {
        switch widgetFamily {
        case .systemMedium:
            mediumLayout
        default:
            smallLayout
        }
    }

    @ViewBuilder
    private var smallLayout: some View {
        if let snapshot = entry.snapshot {
            VStack(alignment: .leading, spacing: 4) {
                Text(snapshot.city)
                    .font(.caption)
                    .lineLimit(1)

                Spacer(minLength: 2)

                Text(snapshot.line1)
                    .font(.caption)
                    .lineLimit(1)

                Text(snapshot.line2)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)

                Text(snapshot.line3)
                    .font(.caption)
                    .lineLimit(1)

                Spacer()

                HStack(spacing: 6) {
                    Text(snapshot.temperatureText)
                        .font(.caption2)
                    Image(systemName: snapshot.iconName)
                        .font(.caption2)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .containerBackground(.fill.tertiary, for: .widget)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("EasyWeather")
                    .font(.headline)
                Text("Open the app to load weather")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .containerBackground(.fill.tertiary, for: .widget)
        }
    }

    private var mediumLayout: some View {
        let periods = entry.snapshot?.periods.isEmpty == false ? entry.snapshot?.periods ?? [] : fallbackPeriods

        return VStack(alignment: .leading, spacing: 10) {
            ForEach(periods) { period in
                HStack(spacing: 10) {
                    Text(period.label)
                        .font(.headline)

                    Spacer()

                    Text(period.temperatureText)
                        .font(.headline)

                    Image(systemName: period.iconName)
                        .font(.headline)
                        .frame(width: 22, height: 22, alignment: .center)
                }
                .frame(height: 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private var fallbackPeriods: [WidgetPeriodSnapshot] {
        [
            WidgetPeriodSnapshot(label: "morning", temperatureText: "--°C", iconName: "cloud"),
            WidgetPeriodSnapshot(label: "noon", temperatureText: "--°C", iconName: "cloud"),
            WidgetPeriodSnapshot(label: "evening", temperatureText: "--°C", iconName: "cloud"),
            WidgetPeriodSnapshot(label: "night", temperatureText: "--°C", iconName: "cloud")
        ]
    }
}

struct EasyWeatherTodayWidget: Widget {
    let kind: String = WidgetStorage.kind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WeatherWidgetProvider()) { entry in
            EasyWeatherTodayWidgetView(entry: entry)
        }
        .configurationDisplayName("EasyWeather Today")
        .description("Shows today's comparison and period weather.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
