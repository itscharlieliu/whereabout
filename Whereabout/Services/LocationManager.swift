import Foundation
import CoreLocation
import MapKit
import SwiftData

@MainActor
final class LocationManager: NSObject, ObservableObject {
    static let shared = LocationManager()

    private let clManager = CLLocationManager()
    var modelContainer: ModelContainer?

    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var isTracking = false
    @Published var lastLocation: CLLocation?

    override init() {
        super.init()
        clManager.delegate = self
        clManager.allowsBackgroundLocationUpdates = true
        authorizationStatus = clManager.authorizationStatus
    }

    func requestPermission() {
        clManager.requestAlwaysAuthorization()
    }

    func startTracking() {
        guard clManager.authorizationStatus == .authorizedAlways ||
              clManager.authorizationStatus == .authorizedWhenInUse else {
            requestPermission()
            return
        }
        // Use significant location changes for occasional background updates (~500m movement)
        clManager.startMonitoringSignificantLocationChanges()
        // Visit monitoring detects when user stays at a place
        clManager.startMonitoringVisits()
        isTracking = true
    }

    func stopTracking() {
        clManager.stopMonitoringSignificantLocationChanges()
        clManager.stopMonitoringVisits()
        isTracking = false
    }

    private func saveLocation(_ location: CLLocation) {
        guard let container = modelContainer else { return }
        let context = ModelContext(container)
        let record = LocationRecord(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            timestamp: location.timestamp,
            altitude: location.altitude,
            speed: location.speed,
            horizontalAccuracy: location.horizontalAccuracy
        )
        context.insert(record)
        do {
            try context.save()
        } catch {
            print("Failed to save location: \(error)")
        }
    }

    private func saveVisit(_ visit: CLVisit) {
        guard let container = modelContainer else { return }
        let context = ModelContext(container)

        // If this is a departure event, update the existing record instead of inserting a duplicate.
        let arrivalDate = visit.arrivalDate
        let existing = try? context.fetch(
            FetchDescriptor<VisitRecord>(
                predicate: #Predicate { $0.arrivalDate == arrivalDate }
            )
        )
        if let record = existing?.first {
            record.departureDate = visit.departureDate
            try? context.save()
            return
        }

        // Arriving somewhere new: close any open visits that predate this arrival.
        closeOpenVisits(before: visit.arrivalDate, in: context)

        let record = VisitRecord(
            latitude: visit.coordinate.latitude,
            longitude: visit.coordinate.longitude,
            arrivalDate: visit.arrivalDate,
            departureDate: visit.departureDate,
            horizontalAccuracy: visit.horizontalAccuracy
        )
        context.insert(record)
        do {
            try context.save()
        } catch {
            print("Failed to save visit: \(error)")
        }

        reverseGeocode(record: record, container: container)
    }

    private func closeOpenVisits(before date: Date, in context: ModelContext) {
        let distantFuture = Date.distantFuture
        let openVisits = (try? context.fetch(FetchDescriptor<VisitRecord>(
            predicate: #Predicate { $0.departureDate == distantFuture && $0.arrivalDate < date }
        ))) ?? []
        for visit in openVisits {
            visit.departureDate = date
        }
        if !openVisits.isEmpty {
            try? context.save()
        }
    }

    private func reverseGeocode(record: VisitRecord, container: ModelContainer) {
        let location = CLLocation(latitude: record.latitude, longitude: record.longitude)
        let visitID = record.persistentModelID

        Task {
            guard let request = MKReverseGeocodingRequest(location: location),
                  let mapItem = try? await request.mapItems.first
            else { return }

            let placemark = mapItem.placemark
            let placeName = mapItem.name ?? placemark.locality
            let address = [placemark.thoroughfare, placemark.locality, placemark.administrativeArea]
                .compactMap { $0 }
                .joined(separator: ", ")

            await MainActor.run {
                let context = ModelContext(container)
                if let visit = context.model(for: visitID) as? VisitRecord {
                    visit.placeName = placeName
                    visit.address = address
                    try? context.save()
                }
            }
        }
    }
}

// MARK: - CLLocationManagerDelegate
extension LocationManager: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationStatus = status
            if status == .authorizedAlways || status == .authorizedWhenInUse {
                if !self.isTracking {
                    self.startTracking()
                }
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let validLocations = locations.filter { $0.horizontalAccuracy >= 0 && $0.horizontalAccuracy < 100 }
        Task { @MainActor in
            for location in validLocations {
                self.lastLocation = location
                self.saveLocation(location)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        Task { @MainActor in
            self.saveVisit(visit)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location manager error: \(error.localizedDescription)")
    }
}
