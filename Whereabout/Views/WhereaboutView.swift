import SwiftUI
import SwiftData
import MapKit

struct WhereaboutView: View {
    let selectedDate: Date

    @Query private var dayLocations: [LocationRecord]
    @Query private var dayVisits: [VisitRecord]

    @State private var selectedVisit: VisitRecord?

    init(selectedDate: Date) {
        self.selectedDate = selectedDate
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: selectedDate)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        _dayLocations = Query(
            filter: #Predicate<LocationRecord> { record in
                record.timestamp >= startOfDay && record.timestamp < endOfDay
            },
            sort: \.timestamp
        )

        _dayVisits = Query(
            filter: #Predicate<VisitRecord> { visit in
                visit.arrivalDate < endOfDay && visit.departureDate >= startOfDay
            },
            sort: \.arrivalDate
        )
    }

    private var totalDistance: Double {
        guard dayLocations.count >= 2 else { return 0 }
        var distance: Double = 0
        for i in 1..<dayLocations.count {
            let prev = CLLocation(latitude: dayLocations[i-1].latitude, longitude: dayLocations[i-1].longitude)
            let curr = CLLocation(latitude: dayLocations[i].latitude, longitude: dayLocations[i].longitude)
            distance += curr.distance(from: prev)
        }
        return distance
    }

    var body: some View {
        VStack(spacing: 0) {
            // Map section
            WhereaboutMapView(locations: dayLocations, visits: dayVisits, selectedVisit: selectedVisit)
                .frame(height: 300)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal)
                .padding(.top, 8)

            // Stats bar
            statsBar
                .padding(.horizontal)
                .padding(.vertical, 12)

            Divider()

            // Timeline list
            if dayVisits.isEmpty && dayLocations.isEmpty {
                emptyState
            } else {
                timelineList
            }
        }
    }

    // MARK: - Stats Bar

    private var statsBar: some View {
        HStack(spacing: 20) {
            StatBadge(
                icon: "figure.walk",
                value: formattedDistance,
                label: "Distance"
            )
            StatBadge(
                icon: "mappin.and.ellipse",
                value: "\(dayVisits.count)",
                label: "Places"
            )
            StatBadge(
                icon: "location.fill",
                value: "\(dayLocations.count)",
                label: "Points"
            )
        }
    }

    private var formattedDistance: String {
        if totalDistance >= 1000 {
            return String(format: "%.1f km", totalDistance / 1000)
        }
        return String(format: "%.0f m", totalDistance)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "location.slash")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No location data")
                .font(.title3)
                .fontWeight(.semibold)
            Text("Location tracking will record your movements throughout the day.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
    }

    // MARK: - Timeline List

    private var timelineList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(dayVisits.enumerated()), id: \.element.id) { index, visit in
                    // Travel segment before visit (if not the first)
                    if index > 0 {
                        travelSegment(from: dayVisits[index - 1], to: visit)
                    }

                    let nextArrival = index + 1 < dayVisits.count ? dayVisits[index + 1].arrivalDate : nil
                    visitRow(visit, inferredDeparture: visit.isOngoing ? nextArrival : nil)
                        .onTapGesture { selectedVisit = visit }
                }

                // If we have locations but no visits, show a simple route summary
                if dayVisits.isEmpty && !dayLocations.isEmpty {
                    routeSummaryRow
                }
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: - Visit Row

    private func visitRow(_ visit: VisitRecord, inferredDeparture: Date? = nil) -> some View {
        let effectiveDeparture = inferredDeparture ?? (visit.isOngoing ? nil : visit.departureDate)
        let stillOngoing = effectiveDeparture == nil

        let displayDuration: String = {
            let end = effectiveDeparture ?? Date.now
            let interval = end.timeIntervalSince(visit.arrivalDate)
            let f = DateComponentsFormatter()
            f.allowedUnits = [.hour, .minute]
            f.unitsStyle = .abbreviated
            return f.string(from: interval) ?? ""
        }()

        return HStack(alignment: .top, spacing: 12) {
            // Timeline indicator
            VStack(spacing: 4) {
                Circle()
                    .fill(stillOngoing ? Color.green : Color.blue)
                    .frame(width: 12, height: 12)
                if !stillOngoing {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(width: 2)
                }
            }
            .frame(width: 12)

            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(visit.placeName ?? "Unknown Place")
                    .font(.headline)

                if let address = visit.address, !address.isEmpty {
                    Text(address)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    Label(visit.formattedArrival, systemImage: "arrow.right.circle")
                    Text("–")
                    if stillOngoing {
                        Label("now", systemImage: "clock.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label(
                            effectiveDeparture!.formatted(date: .omitted, time: .shortened),
                            systemImage: "arrow.left.circle"
                        )
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Text(displayDuration)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(stillOngoing ? Color.green : Color.blue)
                    )
            }

            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Travel Segment

    private func travelSegment(from: VisitRecord, to: VisitRecord) -> some View {
        let fromLocation = CLLocation(latitude: from.latitude, longitude: from.longitude)
        let toLocation = CLLocation(latitude: to.latitude, longitude: to.longitude)
        let distance = toLocation.distance(from: fromLocation)

        let travelTime: TimeInterval = {
            guard !from.isOngoing else { return 0 }
            return to.arrivalDate.timeIntervalSince(from.departureDate)
        }()

        return HStack(alignment: .center, spacing: 12) {
            VStack {
                Rectangle()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(width: 2, height: 30)
            }
            .frame(width: 12)

            HStack(spacing: 6) {
                Image(systemName: "car.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)

                if distance >= 1000 {
                    Text(String(format: "%.1f km", distance / 1000))
                        .font(.caption2)
                } else {
                    Text(String(format: "%.0f m", distance))
                        .font(.caption2)
                }

                if travelTime > 0 {
                    Text("·")
                        .font(.caption2)
                    Text({
                        let f = DateComponentsFormatter()
                        f.allowedUnits = [.hour, .minute]
                        f.unitsStyle = .abbreviated
                        return f.string(from: travelTime) ?? ""
                    }())
                    .font(.caption2)
                }
            }
            .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(.horizontal)
    }

    // MARK: - Route Summary

    private var routeSummaryRow: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 4) {
                Circle()
                    .fill(.blue)
                    .frame(width: 12, height: 12)
            }
            .frame(width: 12)

            VStack(alignment: .leading, spacing: 4) {
                Text("Route recorded")
                    .font(.headline)

                if let first = dayLocations.first, let last = dayLocations.last {
                    Text("\(first.timestamp.formatted(date: .omitted, time: .shortened)) – \(last.timestamp.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(formattedDistance)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(.blue))
            }

            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

// MARK: - Stat Badge

struct StatBadge: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.blue)
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.systemGray6))
        )
    }
}
