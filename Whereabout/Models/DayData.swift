import Foundation
import SwiftData
import CoreLocation

/// A processed visit paired with its effective departure time.
struct FilteredVisit: Identifiable {
    let visit: VisitRecord
    /// nil means the visit is still ongoing (no end time known).
    let effectiveDeparture: Date?

    var id: PersistentIdentifier { visit.persistentModelID }
}

/// Single source of truth for all location and visit data for a given day.
struct DayData {
    /// Raw GPS points for the day, sorted by timestamp.
    let locations: [LocationRecord]
    /// Deduplicated, duration-filtered visits paired with their effective departure times.
    let filteredVisits: [FilteredVisit]
    /// Last known location from the day before (used to anchor the route polyline).
    let priorLocation: LocationRecord?
    /// Last visit that started before today (shown at the top of the timeline).
    let priorVisit: VisitRecord?

    var isEmpty: Bool {
        locations.isEmpty && filteredVisits.isEmpty
    }

    var totalDistance: Double {
        guard locations.count >= 2 else { return 0 }
        var dist: Double = 0
        for i in 1..<locations.count {
            let a = CLLocation(latitude: locations[i-1].latitude, longitude: locations[i-1].longitude)
            let b = CLLocation(latitude: locations[i].latitude, longitude: locations[i].longitude)
            dist += b.distance(from: a)
        }
        return dist
    }

    var formattedDistance: String {
        let measurement = Measurement(value: totalDistance, unit: UnitLength.meters)
        let formatter = MeasurementFormatter()
        formatter.unitOptions = .naturalScale
        formatter.numberFormatter.maximumFractionDigits = 1
        return formatter.string(from: measurement)
    }

    // MARK: - Factory

    private static let minVisitDuration: TimeInterval = 5 * 60

    /// Build a DayData from raw SwiftData query results.
    ///
    /// - Parameters:
    ///   - locations: All LocationRecords for the day (sorted ascending by timestamp).
    ///   - visits: All VisitRecords for the day (sorted ascending by arrivalDate).
    ///   - priorLocation: The most recent LocationRecord *before* the day (limit 1).
    ///   - priorVisit: The most recent VisitRecord *before* the day (limit 1).
    static func build(
        locations: [LocationRecord],
        visits: [VisitRecord],
        priorLocation: LocationRecord?,
        priorVisit: VisitRecord?
    ) -> DayData {
        // Deduplicate: for identical arrivalDate keep the record with a real departure.
        var best: [Date: VisitRecord] = [:]
        for v in visits {
            if let existing = best[v.arrivalDate] {
                if existing.isOngoing && !v.isOngoing { best[v.arrivalDate] = v }
            } else {
                best[v.arrivalDate] = v
            }
        }
        let deduped = visits.filter {
            best[$0.arrivalDate]?.persistentModelID == $0.persistentModelID
        }

        // Compute effective departures and filter out visits shorter than the minimum.
        let filtered: [FilteredVisit] = deduped.enumerated().compactMap { i, visit in
            let nextArrival = i + 1 < deduped.count ? deduped[i + 1].arrivalDate : nil

            // The last ongoing visit is the user's current location — always include it.
            if visit.isOngoing && nextArrival == nil {
                return FilteredVisit(visit: visit, effectiveDeparture: nil)
            }

            let dep: Date?
            if !visit.isOngoing {
                dep = visit.departureDate
            } else {
                // Infer departure from the next visit arrival or first GPS ping after the visit.
                let firstLocationAfter = locations.first { $0.timestamp > visit.arrivalDate }?.timestamp
                dep = [nextArrival, firstLocationAfter].compactMap { $0 }.min()
            }

            let duration = (dep ?? .now).timeIntervalSince(visit.arrivalDate)
            guard duration >= minVisitDuration else { return nil }
            return FilteredVisit(visit: visit, effectiveDeparture: dep)
        }

        return DayData(
            locations: locations,
            filteredVisits: filtered,
            priorLocation: priorLocation,
            priorVisit: priorVisit
        )
    }

    // MARK: - Prior-visit helpers

    /// Inferred departure for the prior (carry-over) visit based on today's earliest data.
    func inferredPriorDeparture() -> Date? {
        guard let prior = priorVisit, prior.isOngoing else { return nil }
        let firstTodayVisit = filteredVisits.first?.visit.arrivalDate
        let firstTodayLocation = locations.first?.timestamp
        return [firstTodayVisit, firstTodayLocation].compactMap { $0 }.min()
    }
}
