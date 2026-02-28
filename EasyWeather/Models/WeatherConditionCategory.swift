import Foundation

enum WeatherConditionCategory: String, Codable, CaseIterable {
    case clear
    case partlyCloudy
    case cloudy
    case fog
    case drizzle
    case rain
    case snow
    case thunderstorm
    case unknown

    var displayName: String {
        switch self {
        case .clear:
            return "Clear"
        case .partlyCloudy:
            return "Partly cloudy"
        case .cloudy:
            return "Cloudy"
        case .fog:
            return "Fog"
        case .drizzle:
            return "Drizzle"
        case .rain:
            return "Rain"
        case .snow:
            return "Snow"
        case .thunderstorm:
            return "Thunderstorm"
        case .unknown:
            return "Unknown"
        }
    }

    static func fromOpenMeteoCode(_ code: Int) -> WeatherConditionCategory {
        switch code {
        case 0:
            return .clear
        case 1, 2:
            return .partlyCloudy
        case 3:
            return .cloudy
        case 45, 48:
            return .fog
        case 51, 53, 55, 56, 57:
            return .drizzle
        case 61, 63, 65, 66, 67, 80, 81, 82:
            return .rain
        case 71, 73, 75, 77, 85, 86:
            return .snow
        case 95, 96, 99:
            return .thunderstorm
        default:
            return .unknown
        }
    }

    static func fromWeatherKitDescription(_ description: String) -> WeatherConditionCategory {
        let normalized = description.lowercased()

        if normalized.contains("thunder") || normalized.contains("storm") {
            return .thunderstorm
        }

        if normalized.contains("snow") || normalized.contains("sleet") || normalized.contains("hail") || normalized.contains("blizzard") {
            return .snow
        }

        if normalized.contains("drizzle") {
            return .drizzle
        }

        if normalized.contains("rain") {
            return .rain
        }

        if normalized.contains("fog") || normalized.contains("haze") || normalized.contains("smoke") {
            return .fog
        }

        if normalized.contains("partly") || normalized.contains("mostly") {
            return .partlyCloudy
        }

        if normalized.contains("cloud") {
            return .cloudy
        }

        if normalized.contains("clear") || normalized.contains("sun") {
            return .clear
        }

        return .unknown
    }
}
