import Combine
import CoreLocation
import Foundation
import UIKit

enum ComparisonMode: String, CaseIterable, Identifiable {
    case today
    case tomorrow

    var id: String { rawValue }
}

enum WeatherDisplayState: Equatable {
    case loading
    case permissionDenied
    case content
    case error
    case unavailable
}

enum RelationKeywordStyle {
    case warmer
    case colder
    case same
}

struct PeriodWeatherRow: Identifiable, Hashable {
    let id: String
    let label: String
    let temperatureCelsius: Double
    let condition: WeatherConditionCategory
}

private enum ComparisonRelation {
    case warmer
    case colder
    case same
}

@MainActor
final class WeatherViewModel: ObservableObject {
    @Published var selectedMode: ComparisonMode = .today {
        didSet {
            rebuildPresentation()
        }
    }

    @Published var displayState: WeatherDisplayState = .loading
    @Published var cityTitle: String = "Current Location"
    @Published var locationLabel: String = "Current Location"
    @Published var comparisonLineOne: String = "today is"
    @Published var comparisonKeyword: String = "SIMILAR"
    @Published var comparisonLineThree: String = "as yesterday"
    @Published var keywordStyle: RelationKeywordStyle = .same
    @Published var periodRows: [PeriodWeatherRow] = []

    @Published var lastUpdatedText: String = "--:--"
    @Published var isOffline: Bool = false
    @Published var errorMessage: String = "Could not load weather. Tap to retry."

    @Published var citySearchQuery: String = ""
    @Published var citySuggestions: [String] = []
    @Published var citySearchStatusMessage: String = ""

    private let weatherService: WeatherServiceProtocol
    private let locationService: LocationService
    private let cacheService: CacheService
    private let citySearchService: CitySearchService
    private let widgetSyncService: WidgetSyncService
    private let timeFormatter: DateFormatter

    private let periodDefinitions: [(label: String, hour: Int)] = [
        ("morning", 8),
        ("noon", 12),
        ("evening", 18),
        ("night", 22)
    ]

    private var hasLoaded = false
    private var activeTask: Task<Void, Never>?
    private var backgroundRefreshTask: Task<Void, Never>?
    private var citySearchTask: Task<Void, Never>?

    private var currentPayload: WeatherPayload?
    private var currentCoordinate: CLLocationCoordinate2D?
    private var currentLocationName: String = "Current Location"

    init(
        weatherService: WeatherServiceProtocol? = nil,
        locationService: LocationService? = nil,
        cacheService: CacheService? = nil,
        citySearchService: CitySearchService? = nil,
        widgetSyncService: WidgetSyncService? = nil
    ) {
        self.weatherService = weatherService ?? CompositeWeatherService()
        self.locationService = locationService ?? LocationService()
        self.cacheService = cacheService ?? CacheService()
        self.citySearchService = citySearchService ?? CitySearchService()
        self.widgetSyncService = widgetSyncService ?? WidgetSyncService()

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = .current
        self.timeFormatter = formatter
    }

    deinit {
        activeTask?.cancel()
        backgroundRefreshTask?.cancel()
        citySearchTask?.cancel()
    }

    func loadInitialWeather() {
        guard !hasLoaded else {
            return
        }

        hasLoaded = true
        fetchFromCurrentLocation(showLoading: true, allowCache: true)
    }

    func refreshTapped() {
        if let currentCoordinate {
            fetchWeather(for: currentCoordinate, locationName: currentLocationName, showLoading: false, allowCache: false)
        } else {
            fetchFromCurrentLocation(showLoading: true, allowCache: false)
        }
    }

    func appBecameActive() {
        if let currentCoordinate {
            fetchWeather(for: currentCoordinate, locationName: currentLocationName, showLoading: false, allowCache: true)
        } else {
            fetchFromCurrentLocation(showLoading: currentPayload == nil, allowCache: true)
        }
    }

    func autoRefreshIfNeeded() {
        guard let currentCoordinate else {
            return
        }

        fetchWeather(for: currentCoordinate, locationName: currentLocationName, showLoading: false, allowCache: false)
    }

    func retryTapped() {
        if let currentCoordinate {
            fetchWeather(for: currentCoordinate, locationName: currentLocationName, showLoading: true, allowCache: false)
        } else {
            fetchFromCurrentLocation(showLoading: true, allowCache: false)
        }
    }

    func citySearchQueryChanged() {
        let query = citySearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        citySearchTask?.cancel()
        citySearchStatusMessage = ""

        guard query.count >= 2 else {
            citySuggestions = []
            return
        }

        citySearchTask = Task { @MainActor in
            let suggestions = await citySearchService.searchCities(matching: query)
            guard !Task.isCancelled else {
                return
            }

            let currentQuery = self.citySearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            guard currentQuery == query else {
                return
            }

            self.citySuggestions = suggestions
        }
    }

    func selectCitySuggestion(_ city: String) {
        citySearchQuery = city
        citySuggestions = []
        useCity(named: city)
    }

    func useTypedCityFromSettings() {
        useCity(named: citySearchQuery)
    }

    func useCityTapped() {
        useTypedCityFromSettings()
    }

    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
            return
        }

        UIApplication.shared.open(url)
    }

    private func useCity(named rawCity: String) {
        let city = rawCity.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !city.isEmpty else {
            return
        }

        runTask {
            if self.currentPayload == nil {
                self.displayState = .loading
            }

            do {
                let coordinate = try await self.locationService.geocodeCity(city)
                self.citySearchStatusMessage = ""
                self.fetchWeather(for: coordinate, locationName: city, showLoading: self.currentPayload == nil, allowCache: true)
            } catch is CancellationError {
                return
            } catch {
                self.citySearchStatusMessage = "Could not find that city."
                self.errorMessage = "Could not load weather. Tap to retry."
                if self.currentPayload == nil {
                    self.displayState = .error
                }
            }
        }
    }

    private func fetchFromCurrentLocation(showLoading: Bool, allowCache: Bool) {
        runTask {
            if showLoading && self.currentPayload == nil {
                self.displayState = .loading
            }

            do {
                let coordinate = try await self.locationService.requestCurrentLocation()
                let city = await self.locationService.reverseGeocodeCity(for: coordinate)
                let locationName = city ?? "Current Location"
                self.fetchWeather(for: coordinate, locationName: locationName, showLoading: showLoading, allowCache: allowCache)
            } catch is CancellationError {
                return
            } catch let locationError as LocationServiceError {
                if locationError == .permissionDenied {
                    if self.currentPayload == nil {
                        self.displayState = .permissionDenied
                    }
                } else {
                    self.errorMessage = "Could not load weather. Tap to retry."
                    if self.currentPayload == nil {
                        self.displayState = .error
                    }
                }
            } catch {
                self.errorMessage = "Could not load weather. Tap to retry."
                if self.currentPayload == nil {
                    self.displayState = .error
                }
            }
        }
    }

    private func fetchWeather(
        for coordinate: CLLocationCoordinate2D,
        locationName: String,
        showLoading: Bool,
        allowCache: Bool
    ) {
        runTask {
            self.currentCoordinate = coordinate
            self.currentLocationName = locationName
            self.locationLabel = locationName

            if allowCache, let cachedRecord = self.cacheService.loadValid(for: coordinate) {
                self.applyPayload(
                    cachedRecord.payload,
                    locationName: locationName,
                    timestamp: cachedRecord.timestamp,
                    isOffline: false
                )

                self.backgroundRefreshTask?.cancel()
                self.backgroundRefreshTask = Task { @MainActor in
                    await self.refreshFromNetwork(for: coordinate, locationName: locationName)
                }
                return
            }

            if showLoading && self.currentPayload == nil {
                self.displayState = .loading
            }

            await self.refreshFromNetwork(for: coordinate, locationName: locationName)
        }
    }

    private func refreshFromNetwork(for coordinate: CLLocationCoordinate2D, locationName: String) async {
        do {
            let payload = try await weatherService.fetchDailyWeather(for: coordinate)
            guard !Task.isCancelled else {
                return
            }

            cacheService.save(payload: payload, for: coordinate)

            applyPayload(
                payload,
                locationName: locationName,
                timestamp: Date(),
                isOffline: false
            )
        } catch is CancellationError {
            return
        } catch let weatherError as WeatherServiceError {
            applyError(weatherError, coordinate: coordinate, locationName: locationName)
        } catch {
            applyError(nil, coordinate: coordinate, locationName: locationName)
        }
    }

    private func applyError(
        _ weatherError: WeatherServiceError?,
        coordinate: CLLocationCoordinate2D,
        locationName: String
    ) {
        if let cachedRecord = cacheService.load(for: coordinate) {
            applyPayload(
                cachedRecord.payload,
                locationName: locationName,
                timestamp: cachedRecord.timestamp,
                isOffline: true
            )
            return
        }

        if weatherError == .incompleteData {
            displayState = .unavailable
            return
        }

        errorMessage = "Could not load weather. Tap to retry."
        displayState = .error
    }

    private func applyPayload(
        _ payload: WeatherPayload,
        locationName: String,
        timestamp: Date,
        isOffline: Bool
    ) {
        currentPayload = payload
        currentLocationName = locationName
        locationLabel = locationName
        cityTitle = cityOnly(from: locationName)
        lastUpdatedText = timeFormatter.string(from: timestamp)
        self.isOffline = isOffline

        if citySearchQuery.isEmpty || citySearchQuery == "Current Location" {
            citySearchQuery = locationName
        }

        updateWidgetSnapshot(payload: payload, locationName: locationName)
        rebuildPresentation()
    }

    private func rebuildPresentation() {
        guard let payload = currentPayload else {
            return
        }

        let anchors = DateHelpers.dayAnchors(timezoneIdentifier: payload.timezoneIdentifier)

        let focusTargetDate: Date
        let referenceTargetDate: Date

        switch selectedMode {
        case .today:
            focusTargetDate = anchors.today
            referenceTargetDate = anchors.yesterday
        case .tomorrow:
            focusTargetDate = anchors.tomorrow
            referenceTargetDate = anchors.today
        }

        guard let focusDay = DateHelpers.matchingDay(
            in: payload.daily,
            targetDay: focusTargetDate,
            timezoneIdentifier: payload.timezoneIdentifier
        ),
        let referenceDay = DateHelpers.matchingDay(
            in: payload.daily,
            targetDay: referenceTargetDate,
            timezoneIdentifier: payload.timezoneIdentifier
        ) else {
            displayState = .unavailable
            return
        }

        let delta = focusDay.comparisonTempCelsius - referenceDay.comparisonTempCelsius
        let relation = relation(for: delta)

        comparisonLineOne = selectedMode == .today ? "today is" : "tomorrow will be"
        comparisonKeyword = keyword(for: relation)
        keywordStyle = keywordStyle(for: relation)
        comparisonLineThree = trailingLine(for: selectedMode, relation: relation)
        periodRows = buildPeriodRows(for: focusDay, payload: payload)

        displayState = .content
    }

    private func buildPeriodRows(for focusDay: DailyWeather, payload: WeatherPayload) -> [PeriodWeatherRow] {
        let calendar = DateHelpers.calendar(for: payload.timezoneIdentifier)
        let dayStart = calendar.startOfDay(for: focusDay.date)

        let sameDayHours = payload.hourly.filter { hourly in
            calendar.isDate(hourly.date, inSameDayAs: dayStart)
        }

        return periodDefinitions.map { definition in
            let targetDate = calendar.date(bySettingHour: definition.hour, minute: 0, second: 0, of: dayStart) ?? dayStart

            if let nearestHour = nearestHourly(to: targetDate, from: sameDayHours) {
                return PeriodWeatherRow(
                    id: definition.label,
                    label: definition.label,
                    temperatureCelsius: nearestHour.temperatureCelsius,
                    condition: nearestHour.condition
                )
            }

            return PeriodWeatherRow(
                id: definition.label,
                label: definition.label,
                temperatureCelsius: fallbackTemperature(for: definition.label, daily: focusDay),
                condition: focusDay.condition
            )
        }
    }

    private func nearestHourly(to targetDate: Date, from hours: [HourlyWeather]) -> HourlyWeather? {
        hours.min { left, right in
            abs(left.date.timeIntervalSince(targetDate)) < abs(right.date.timeIntervalSince(targetDate))
        }
    }

    private func fallbackTemperature(for label: String, daily: DailyWeather) -> Double {
        let range = daily.highCelsius - daily.lowCelsius

        switch label {
        case "morning":
            return daily.lowCelsius + range * 0.25
        case "noon":
            return daily.lowCelsius + range * 0.85
        case "evening":
            return daily.lowCelsius + range * 0.55
        case "night":
            return daily.lowCelsius + range * 0.15
        default:
            return daily.comparisonTempCelsius
        }
    }

    private func relation(for delta: Double) -> ComparisonRelation {
        if abs(delta) < 0.5 {
            return .same
        }

        if delta >= 0.5 {
            return .warmer
        }

        return .colder
    }

    private func keyword(for relation: ComparisonRelation) -> String {
        switch relation {
        case .warmer:
            return "WARMER"
        case .colder:
            return "COLDER"
        case .same:
            return "SIMILAR"
        }
    }

    private func keywordStyle(for relation: ComparisonRelation) -> RelationKeywordStyle {
        switch relation {
        case .warmer:
            return .warmer
        case .colder:
            return .colder
        case .same:
            return .same
        }
    }

    private func trailingLine(for mode: ComparisonMode, relation: ComparisonRelation) -> String {
        switch mode {
        case .today:
            return relation == .same ? "as yesterday" : "than yesterday"
        case .tomorrow:
            return relation == .same ? "as today" : "than today"
        }
    }

    private func runTask(_ work: @escaping @MainActor () async -> Void) {
        backgroundRefreshTask?.cancel()
        activeTask?.cancel()
        activeTask = Task { @MainActor in
            await work()
        }
    }

    private func cityOnly(from location: String) -> String {
        let parts = location
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return parts.first ?? location
    }

    private func updateWidgetSnapshot(payload: WeatherPayload, locationName: String) {
        let anchors = DateHelpers.dayAnchors(timezoneIdentifier: payload.timezoneIdentifier)

        guard let today = DateHelpers.matchingDay(
            in: payload.daily,
            targetDay: anchors.today,
            timezoneIdentifier: payload.timezoneIdentifier
        ),
        let yesterday = DateHelpers.matchingDay(
            in: payload.daily,
            targetDay: anchors.yesterday,
            timezoneIdentifier: payload.timezoneIdentifier
        ) else {
            return
        }

        let delta = today.comparisonTempCelsius - yesterday.comparisonTempCelsius
        let relation = relation(for: delta)
        let periodSnapshots = buildPeriodRows(for: today, payload: payload).map { row in
            WidgetPeriodSnapshot(
                label: row.label,
                temperatureText: "\(Int(row.temperatureCelsius.rounded()))°C",
                iconName: IconMapper.symbolName(for: row.condition)
            )
        }

        let snapshot = WeatherWidgetSnapshot(
            city: cityOnly(from: locationName),
            line1: "today is",
            line2: keyword(for: relation),
            line3: trailingLine(for: .today, relation: relation),
            temperatureText: "\(Int(today.comparisonTempCelsius.rounded()))°C",
            iconName: IconMapper.symbolName(for: today.condition),
            periods: periodSnapshots,
            updatedAt: Date()
        )

        widgetSyncService.saveTodaySnapshot(snapshot)
    }
}
