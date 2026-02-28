import CoreLocation
import Foundation

struct OpenMeteoService: WeatherServiceProtocol {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchDailyWeather(for coordinate: CLLocationCoordinate2D) async throws -> WeatherPayload {
        guard let url = buildURL(for: coordinate) else {
            throw WeatherServiceError.invalidRequest
        }

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw WeatherServiceError.invalidResponse
        }

        let decoder = JSONDecoder()
        let openMeteoResponse = try decoder.decode(OpenMeteoResponse.self, from: data)
        let timezone = TimeZone(identifier: openMeteoResponse.timezone) ?? .current

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timezone
        formatter.dateFormat = "yyyy-MM-dd"

        let hourlyFormatter = DateFormatter()
        hourlyFormatter.calendar = Calendar(identifier: .gregorian)
        hourlyFormatter.locale = Locale(identifier: "en_US_POSIX")
        hourlyFormatter.timeZone = timezone
        hourlyFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm"

        let count = min(
            openMeteoResponse.daily.time.count,
            openMeteoResponse.daily.temperatureMax.count,
            openMeteoResponse.daily.temperatureMin.count,
            openMeteoResponse.daily.weatherCode.count
        )

        guard count > 0 else {
            throw WeatherServiceError.incompleteData
        }

        var daily: [DailyWeather] = []
        daily.reserveCapacity(count)

        for index in 0..<count {
            guard let dayDate = formatter.date(from: openMeteoResponse.daily.time[index]) else {
                continue
            }

            let high = openMeteoResponse.daily.temperatureMax[index]
            let low = openMeteoResponse.daily.temperatureMin[index]
            let condition = WeatherConditionCategory.fromOpenMeteoCode(openMeteoResponse.daily.weatherCode[index])

            daily.append(
                DailyWeather(
                    date: dayDate,
                    highCelsius: high,
                    lowCelsius: low,
                    condition: condition
                )
            )
        }

        guard !daily.isEmpty else {
            throw WeatherServiceError.incompleteData
        }

        let hourlyCount = min(
            openMeteoResponse.hourly.time.count,
            openMeteoResponse.hourly.temperature.count,
            openMeteoResponse.hourly.weatherCode.count
        )

        var hourly: [HourlyWeather] = []
        hourly.reserveCapacity(hourlyCount)

        for index in 0..<hourlyCount {
            guard let hourDate = hourlyFormatter.date(from: openMeteoResponse.hourly.time[index]) else {
                continue
            }

            hourly.append(
                HourlyWeather(
                    date: hourDate,
                    temperatureCelsius: openMeteoResponse.hourly.temperature[index],
                    condition: WeatherConditionCategory.fromOpenMeteoCode(openMeteoResponse.hourly.weatherCode[index])
                )
            )
        }

        return WeatherPayload(
            timezoneIdentifier: timezone.identifier,
            daily: daily,
            hourly: hourly,
            source: "Open-Meteo"
        )
    }

    private func buildURL(for coordinate: CLLocationCoordinate2D) -> URL? {
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
}
