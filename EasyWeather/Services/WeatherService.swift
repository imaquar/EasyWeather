import CoreLocation
import Foundation

protocol WeatherServiceProtocol {
    func fetchDailyWeather(for coordinate: CLLocationCoordinate2D) async throws -> WeatherPayload
}

struct WeatherPayload: Codable {
    let timezoneIdentifier: String
    let daily: [DailyWeather]
    let hourly: [HourlyWeather]
    let source: String
}

enum WeatherServiceError: LocalizedError {
    case invalidRequest
    case invalidResponse
    case incompleteData
    case weatherKitUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidRequest:
            return "Invalid weather request."
        case .invalidResponse:
            return "Invalid weather response."
        case .incompleteData:
            return "Weather data unavailable."
        case .weatherKitUnavailable:
            return "WeatherKit is unavailable."
        }
    }
}

struct CompositeWeatherService: WeatherServiceProtocol {
    private let primaryService: WeatherServiceProtocol?
    private let fallbackService: WeatherServiceProtocol

    init(
        primaryService: WeatherServiceProtocol? = WeatherKitService.availableService(),
        fallbackService: WeatherServiceProtocol = OpenMeteoService()
    ) {
        self.primaryService = primaryService
        self.fallbackService = fallbackService
    }

    func fetchDailyWeather(for coordinate: CLLocationCoordinate2D) async throws -> WeatherPayload {
        if let primaryService {
            do {
                return try await primaryService.fetchDailyWeather(for: coordinate)
            } catch {
                return try await fallbackService.fetchDailyWeather(for: coordinate)
            }
        }

        return try await fallbackService.fetchDailyWeather(for: coordinate)
    }
}
