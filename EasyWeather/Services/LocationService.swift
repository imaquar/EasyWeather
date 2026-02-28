@preconcurrency import CoreLocation
import Foundation
import MapKit

enum LocationServiceError: LocalizedError {
    case permissionDenied
    case unableToDetermine
    case geocodingFailed

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Location permission denied."
        case .unableToDetermine:
            return "Could not determine location."
        case .geocodingFailed:
            return "Could not find that city."
        }
    }
}

@MainActor
final class LocationService: NSObject, CLLocationManagerDelegate {
    private let manager: CLLocationManager

    private var authorizationContinuation: CheckedContinuation<CLAuthorizationStatus, Never>?
    private var locationContinuation: CheckedContinuation<CLLocationCoordinate2D, Error>?

    override init() {
        manager = CLLocationManager()
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    var authorizationStatus: CLAuthorizationStatus {
        manager.authorizationStatus
    }

    func requestCurrentLocation() async throws -> CLLocationCoordinate2D {
        let status = await resolvedAuthorizationStatus()

        guard status == .authorizedWhenInUse || status == .authorizedAlways else {
            throw LocationServiceError.permissionDenied
        }

        return try await withCheckedThrowingContinuation { continuation in
            locationContinuation = continuation
            manager.requestLocation()
        }
    }

    func geocodeCity(_ city: String) async throws -> CLLocationCoordinate2D {
        guard let request = MKGeocodingRequest(addressString: city) else {
            throw LocationServiceError.geocodingFailed
        }

        let mapItems = try await request.mapItems
        guard let coordinate = mapItems.first?.location.coordinate else {
            throw LocationServiceError.geocodingFailed
        }

        return coordinate
    }

    func reverseGeocodeCity(for coordinate: CLLocationCoordinate2D) async -> String? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let request = MKReverseGeocodingRequest(location: location) else {
            return nil
        }

        do {
            let mapItems = try await request.mapItems
            let first = mapItems.first

            return first?.addressRepresentations?.cityName
                ?? first?.addressRepresentations?.cityWithContext
                ?? first?.name
                ?? first?.address?.shortAddress
                ?? first?.address?.fullAddress
        } catch {
            return nil
        }
    }

    private func resolvedAuthorizationStatus() async -> CLAuthorizationStatus {
        let current = manager.authorizationStatus

        guard current == .notDetermined else {
            return current
        }

        return await withCheckedContinuation { continuation in
            authorizationContinuation = continuation
            manager.requestWhenInUseAuthorization()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard let continuation = authorizationContinuation else {
            return
        }

        let status = manager.authorizationStatus
        guard status != .notDetermined else {
            return
        }

        authorizationContinuation = nil
        continuation.resume(returning: status)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let continuation = locationContinuation else {
            return
        }

        locationContinuation = nil

        guard let coordinate = locations.last?.coordinate else {
            continuation.resume(throwing: LocationServiceError.unableToDetermine)
            return
        }

        continuation.resume(returning: coordinate)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard let continuation = locationContinuation else {
            return
        }

        locationContinuation = nil
        continuation.resume(throwing: error)
    }
}
