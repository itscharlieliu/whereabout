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

    static let trackingEnabledKey = "trackingEnabled"
    static let webhookURLKey = "webhookURL"
    static let webhookBearerTokenKey = "webhookBearerToken"

    /// Whether the user has chosen to enable tracking (persisted across launches).
    var trackingEnabledPreference: Bool {
        get {
            let val = UserDefaults.standard.object(forKey: Self.trackingEnabledKey) as? Bool ?? true
            return val
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.trackingEnabledKey)
        }
    }

    /// Optional webhook URL to ping on visit arrive/depart events.
    var webhookURL: String {
        get { UserDefaults.standard.string(forKey: Self.webhookURLKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: Self.webhookURLKey) }
    }

    /// Optional bearer token sent as `Authorization: Bearer <token>` with webhook requests.
    var webhookBearerToken: String {
        get { UserDefaults.standard.string(forKey: Self.webhookBearerTokenKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: Self.webhookBearerTokenKey) }
    }

    func startTracking() {
        guard clManager.authorizationStatus == .authorizedAlways ||
              clManager.authorizationStatus == .authorizedWhenInUse else {
            requestPermission()
            return
        }
        clManager.startMonitoringSignificantLocationChanges()
        clManager.startMonitoringVisits()
        isTracking = true
        trackingEnabledPreference = true
    }

    func stopTracking() {
        clManager.stopMonitoringSignificantLocationChanges()
        clManager.stopMonitoringVisits()
        isTracking = false
        trackingEnabledPreference = false
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

        // If arrivalDate is distantPast, iOS started monitoring mid-visit and doesn't
        // know the real start time. Use now as a best-effort arrival date.
        let arrivalDate = visit.arrivalDate == .distantPast ? Date() : visit.arrivalDate
        let existing = try? context.fetch(
            FetchDescriptor<VisitRecord>(
                predicate: #Predicate { $0.arrivalDate == arrivalDate }
            )
        )
        if let record = existing?.first {
            record.departureDate = visit.departureDate
            try? context.save()
            pingWebhook(
                event: "depart",
                latitude: record.latitude,
                longitude: record.longitude,
                placeName: record.placeName,
                address: record.address
            )
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

        pingWebhook(
            event: "arrive",
            latitude: visit.coordinate.latitude,
            longitude: visit.coordinate.longitude,
            placeName: nil,
            address: nil
        )
        reverseGeocode(record: record, container: container)
    }

    private func pingWebhook(event: String, latitude: Double, longitude: Double, placeName: String?, address: String?) {
        let urlString = webhookURL
        guard !urlString.isEmpty, let url = URL(string: urlString) else { return }

        var payload: [String: Any] = [
            "event": event,
            "latitude": latitude,
            "longitude": longitude,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        if let placeName { payload["place_name"] = placeName }
        if let address { payload["address"] = address }

        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let token = webhookBearerToken
        if !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = body

        URLSession.shared.dataTask(with: request) { _, response, error in
            let timestamp = ISO8601DateFormatter().string(from: Date())
            if let error {
                LocationManager.appendWebhookLog("[\(timestamp)] [\(event)] FAILED — \(error.localizedDescription) → \(urlString)")
            } else if let http = response as? HTTPURLResponse {
                let status = (200...299).contains(http.statusCode) ? "OK \(http.statusCode)" : "ERROR \(http.statusCode)"
                LocationManager.appendWebhookLog("[\(timestamp)] [\(event)] \(status) → \(urlString)")
            }
        }.resume()
    }

    nonisolated static var webhookLogURL: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("webhook_log.txt")
    }

    private nonisolated static func appendWebhookLog(_ line: String) {
        guard let fileURL = webhookLogURL else { return }
        let entry = (line + "\n").data(using: .utf8) ?? Data()
        if FileManager.default.fileExists(atPath: fileURL.path) {
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                handle.seekToEndOfFile()
                handle.write(entry)
                try? handle.close()
            }
        } else {
            try? entry.write(to: fileURL, options: .atomic)
        }
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

            let addressRep = mapItem.addressRepresentations
            let placeName = mapItem.name ?? addressRep?.cityName
            let address = [mapItem.address?.shortAddress, addressRep?.regionName]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
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
                if !self.isTracking &&  self.trackingEnabledPreference{
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
