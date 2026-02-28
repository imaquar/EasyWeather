import Foundation

struct HourlyWeather: Codable, Hashable {
    let date: Date
    let temperatureCelsius: Double
    let condition: WeatherConditionCategory
}
