import Foundation

struct OpenMeteoResponse: Decodable {
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
            case weatherCode = "weathercode"
            case weatherCodeAlt = "weather_code"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            time = try container.decode([String].self, forKey: .time)
            temperatureMax = try container.decode([Double].self, forKey: .temperatureMax)
            temperatureMin = try container.decode([Double].self, forKey: .temperatureMin)
            weatherCode = try container.decodeIfPresent([Int].self, forKey: .weatherCodeAlt)
                ?? container.decode([Int].self, forKey: .weatherCode)
        }
    }

    struct Hourly: Decodable {
        let time: [String]
        let temperature: [Double]
        let weatherCode: [Int]

        private enum CodingKeys: String, CodingKey {
            case time
            case temperature = "temperature_2m"
            case weatherCode = "weathercode"
            case weatherCodeAlt = "weather_code"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            time = try container.decode([String].self, forKey: .time)
            temperature = try container.decode([Double].self, forKey: .temperature)
            weatherCode = try container.decodeIfPresent([Int].self, forKey: .weatherCodeAlt)
                ?? container.decode([Int].self, forKey: .weatherCode)
        }
    }
}
