import Foundation

struct DailyWeather: Codable, Hashable {
    let date: Date
    let highCelsius: Double
    let lowCelsius: Double
    let condition: WeatherConditionCategory

    var comparisonTempCelsius: Double {
        ((highCelsius + lowCelsius) / 2).roundedToSingleDecimal()
    }

    var highRounded: Int {
        Int(highCelsius.rounded())
    }

    var lowRounded: Int {
        Int(lowCelsius.rounded())
    }
}

private extension Double {
    func roundedToSingleDecimal() -> Double {
        (self * 10).rounded() / 10
    }
}
