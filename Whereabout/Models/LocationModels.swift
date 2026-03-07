import Foundation
import SwiftData
import CoreLocation

@Model
final class LocationRecord {
    var latitude: Double
    var longitude: Double
    var timestamp: Date
    var altitude: Double
    var speed: Double
    var horizontalAccuracy: Double

    init(
        latitude: Double,
        longitude: Double,
        timestamp: Date,
        altitude: Double = 0,
        speed: Double = -1,
        horizontalAccuracy: Double = 0
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.timestamp = timestamp
        self.altitude = altitude
        self.speed = speed
        self.horizontalAccuracy = horizontalAccuracy
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

@Model
final class VisitRecord {
    var latitude: Double
    var longitude: Double
    var arrivalDate: Date
    var departureDate: Date
    var horizontalAccuracy: Double
    var placeName: String?
    var address: String?

    init(
        latitude: Double,
        longitude: Double,
        arrivalDate: Date,
        departureDate: Date,
        horizontalAccuracy: Double,
        placeName: String? = nil,
        address: String? = nil
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.arrivalDate = arrivalDate
        self.departureDate = departureDate
        self.horizontalAccuracy = horizontalAccuracy
        self.placeName = placeName
        self.address = address
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var isOngoing: Bool {
        departureDate == Date.distantFuture
    }

    var duration: TimeInterval {
        if isOngoing {
            return Date.now.timeIntervalSince(arrivalDate)
        }
        return departureDate.timeIntervalSince(arrivalDate)
    }

    var formattedDuration: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: duration) ?? ""
    }

    var formattedArrival: String {
        arrivalDate.formatted(date: .omitted, time: .shortened)
    }

    var formattedDeparture: String {
        if isOngoing { return "now" }
        return departureDate.formatted(date: .omitted, time: .shortened)
    }
}
