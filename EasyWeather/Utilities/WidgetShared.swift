import Foundation

#if canImport(WidgetKit)
import WidgetKit
#endif

enum WidgetShared {
    static let kind = "EasyWeatherTodayWidget"
    static let appGroupID = "group.aquariusss.easyweather"
    static let snapshotKey = "easyweather.widget.today.snapshot"
}

struct WeatherWidgetSnapshot: Codable {
    let city: String
    let line1: String
    let line2: String
    let line3: String
    let temperatureText: String
    let iconName: String
    let periods: [WidgetPeriodSnapshot]
    let updatedAt: Date

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
}

struct WidgetPeriodSnapshot: Codable {
    let label: String
    let temperatureText: String
    let iconName: String
}

@MainActor
final class WidgetSyncService {
    func saveTodaySnapshot(_ snapshot: WeatherWidgetSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else {
            return
        }

        if let sharedDefaults = UserDefaults(suiteName: WidgetShared.appGroupID) {
            sharedDefaults.set(data, forKey: WidgetShared.snapshotKey)
        } else {
            UserDefaults.standard.set(data, forKey: WidgetShared.snapshotKey)
        }

        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetShared.kind)
        #endif
    }
}
