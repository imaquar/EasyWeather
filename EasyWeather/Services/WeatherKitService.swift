import CoreLocation
import Foundation

#if canImport(WeatherKit)
import WeatherKit

struct WeatherKitService: WeatherServiceProtocol {
    private let weatherService: WeatherKit.WeatherService

    init(weatherService: WeatherKit.WeatherService = WeatherKit.WeatherService()) {
        self.weatherService = weatherService
    }

    func fetchDailyWeather(for coordinate: CLLocationCoordinate2D) async throws -> WeatherPayload {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let weather = try await weatherService.weather(for: location)

        let daily = weather.dailyForecast.forecast.map { day in
            DailyWeather(
                date: day.date,
                highCelsius: day.highTemperature.converted(to: .celsius).value,
                lowCelsius: day.lowTemperature.converted(to: .celsius).value,
                condition: WeatherConditionCategory.fromWeatherKitDescription(String(describing: day.condition))
            )
        }

        let hourly = weather.hourlyForecast.forecast.map { hour in
            HourlyWeather(
                date: hour.date,
                temperatureCelsius: hour.temperature.converted(to: .celsius).value,
                condition: WeatherConditionCategory.fromWeatherKitDescription(String(describing: hour.condition))
            )
        }

        guard !daily.isEmpty else {
            throw WeatherServiceError.incompleteData
        }

        return WeatherPayload(
            timezoneIdentifier: TimeZone.current.identifier,
            daily: daily,
            hourly: hourly,
            source: "WeatherKit"
        )
    }

    static func availableService() -> WeatherServiceProtocol? {
        guard weatherKitEnabledByConfiguration() else {
            return nil
        }

        return WeatherKitService()
    }

    private static func weatherKitEnabledByConfiguration() -> Bool {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "UseWeatherKit") else {
            // Default to Open-Meteo unless WeatherKit is explicitly enabled.
            return false
        }

        if let flag = value as? Bool {
            return flag
        }

        if let text = value as? String {
            return NSString(string: text).boolValue
        }

        return false
    }
}
#else
struct WeatherKitService: WeatherServiceProtocol {
    func fetchDailyWeather(for coordinate: CLLocationCoordinate2D) async throws -> WeatherPayload {
        throw WeatherServiceError.weatherKitUnavailable
    }

    static func availableService() -> WeatherServiceProtocol? {
        nil
    }
}
#endif
