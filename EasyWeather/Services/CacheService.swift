import CoreLocation
import Foundation

struct CachedWeatherRecord {
    let timestamp: Date
    let payload: WeatherPayload
}

final class CacheService {
    private struct CachedEntry: Codable {
        let timestamp: Date
        let payload: WeatherPayload
    }

    private let userDefaults: UserDefaults
    private let ttl: TimeInterval

    init(userDefaults: UserDefaults = .standard, ttl: TimeInterval = 30 * 60) {
        self.userDefaults = userDefaults
        self.ttl = ttl
    }

    func save(payload: WeatherPayload, for coordinate: CLLocationCoordinate2D) {
        let entry = CachedEntry(timestamp: Date(), payload: payload)

        guard let data = try? JSONEncoder().encode(entry) else {
            return
        }

        userDefaults.set(data, forKey: cacheKey(for: coordinate))
    }

    func load(for coordinate: CLLocationCoordinate2D) -> CachedWeatherRecord? {
        let key = cacheKey(for: coordinate)

        guard let data = userDefaults.data(forKey: key),
              let entry = try? JSONDecoder().decode(CachedEntry.self, from: data)
        else {
            return nil
        }

        return CachedWeatherRecord(timestamp: entry.timestamp, payload: entry.payload)
    }

    func loadValid(for coordinate: CLLocationCoordinate2D) -> CachedWeatherRecord? {
        guard let record = load(for: coordinate) else {
            return nil
        }

        let age = Date().timeIntervalSince(record.timestamp)
        return age <= ttl ? record : nil
    }

    private func cacheKey(for coordinate: CLLocationCoordinate2D) -> String {
        let roundedLat = round(coordinate.latitude * 100) / 100
        let roundedLon = round(coordinate.longitude * 100) / 100
        return String(format: "easyWeather.cache.%.2f.%.2f", roundedLat, roundedLon)
    }
}
