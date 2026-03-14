import SwiftUI
import SwiftData
import MapKit

struct WhereaboutView: View {
    let selectedDate: Date

    @Query private var dayLocations: [LocationRecord]
    @Query private var dayVisits: [VisitRecord]
    @Query private var priorLocations: [LocationRecord]
    @Query private var priorVisits: [VisitRecord]

    @State private var selectedVisit: VisitRecord?

    init(selectedDate: Date) {
        self.selectedDate = selectedDate

        // Build day boundaries in the device's local timezone.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
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
                visit.arrivalDate >= startOfDay && visit.arrivalDate < endOfDay
            },
            sort: \.arrivalDate
        )

        var priorLocationsDescriptor = FetchDescriptor<LocationRecord>(
            predicate: #Predicate { $0.timestamp < startOfDay },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        priorLocationsDescriptor.fetchLimit = 1
        _priorLocations = Query(priorLocationsDescriptor)

        var priorVisitsDescriptor = FetchDescriptor<VisitRecord>(
            predicate: #Predicate { $0.arrivalDate < startOfDay },
            sortBy: [SortDescriptor(\.arrivalDate, order: .reverse)]
        )
        priorVisitsDescriptor.fetchLimit = 1
        _priorVisits = Query(priorVisitsDescriptor)
    }

    /// Single source of truth for all processed day data.
    private var dayData: DayData {
        DayData.build(
            locations: dayLocations,
            visits: dayVisits,
            priorLocation: priorLocations.first,
            priorVisit: priorVisits.first
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            // Map
            WhereaboutMapView(dayData: dayData, selectedVisit: selectedVisit)
                .frame(height: 300)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal)
                .padding(.top, 8)

            // Stats bar
            statsBar
                .padding(.horizontal)
                .padding(.vertical, 12)

            Divider()

            // Timeline
            if dayData.isEmpty {
                emptyState
            } else {
                timelineList
            }
        }
    }

    // MARK: - Stats Bar

    private var statsBar: some View {
        HStack(spacing: 20) {
            StatBadge(icon: "road.lanes",          value: dayData.formattedDistance, label: "Distance")
            StatBadge(icon: "mappin.and.ellipse",  value: "\(dayData.filteredVisits.count)", label: "Places")
            StatBadge(icon: "location.fill",       value: "\(dayData.locations.count)", label: "Points")
        }
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
                // Prior (carry-over) visit from the previous day
                if let prior = dayData.priorVisit {
                    visitRow(prior, inferredDeparture: dayData.inferredPriorDeparture())
                        .onTapGesture { selectedVisit = prior }
                }

                // Today's visits
                ForEach(dayData.filteredVisits) { item in
                    visitRow(
                        item.visit,
                        inferredDeparture: item.visit.isOngoing ? item.effectiveDeparture : nil
                    )
                    .onTapGesture { selectedVisit = item.visit }
                }

                // If we have GPS points but no visits, show a simple route summary.
                if dayData.filteredVisits.isEmpty && !dayData.locations.isEmpty {
                    routeSummaryRow
                }
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: - Visit Row

    @ViewBuilder
    private func visitRow(_ visit: VisitRecord, inferredDeparture: Date? = nil) -> some View {
        if visit.arrivalDate == .distantPast {
            startingVisitRow(visit, inferredDeparture: inferredDeparture)
        } else {
            let effectiveDeparture = inferredDeparture ?? (visit.isOngoing ? nil : visit.departureDate)
            let stillOngoing = effectiveDeparture == nil

            let displayDuration: String = {
                let end = effectiveDeparture ?? .now
                let f = DateComponentsFormatter()
                f.allowedUnits = [.hour, .minute]
                f.unitsStyle = .abbreviated
                return f.string(from: end.timeIntervalSince(visit.arrivalDate)) ?? ""
            }()

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(stillOngoing ? Color.green : Color.blue)
                        .frame(width: 12, height: 12)
                    Text(visit.placeName ?? "Unknown Place")
                        .font(.headline)
                    Spacer()
                }

                if let address = visit.address, !address.isEmpty {
                    Text(address)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 20)
                }

                HStack(spacing: 8) {
                    Label(visit.formattedArrival, systemImage: "figure.walk.arrival")
                    Text("–")
                    if stillOngoing {
                        Label("now", systemImage: "clock.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label(
                            effectiveDeparture!.formatted(date: .omitted, time: .shortened),
                            systemImage: "figure.walk.departure"
                        )
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 20)

                if displayDuration != "" {
                    Text(displayDuration)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(stillOngoing ? Color.green : Color.blue))
                        .padding(.leading, 20)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private func startingVisitRow(_ visit: VisitRecord, inferredDeparture: Date? = nil) -> some View {
        let effectiveDeparture = inferredDeparture ?? (visit.isOngoing ? nil : visit.departureDate)
        let stillOngoing = effectiveDeparture == nil

        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Circle()
                    .fill(stillOngoing ? Color.green : Color.blue)
                    .frame(width: 12, height: 12)
                Text(visit.placeName ?? "Unknown Place")
                    .font(.headline)
                Spacer()
            }

            if let address = visit.address, !address.isEmpty {
                Text(address)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 20)
            }

            HStack(spacing: 8) {
                Label("Started here", systemImage: "mappin.and.ellipse")
                Text("–")
                if stillOngoing {
                    Label("now", systemImage: "clock.fill")
                        .foregroundStyle(.green)
                } else {
                    Label(
                        effectiveDeparture!.formatted(date: .omitted, time: .shortened),
                        systemImage: "figure.walk.departure"
                    )
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.leading, 20)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Route Summary Row

    private var routeSummaryRow: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(.blue)
                .frame(width: 12, height: 12)

            VStack(alignment: .leading, spacing: 4) {
                Text("Route recorded")
                    .font(.headline)

                if let first = dayData.locations.first, let last = dayData.locations.last {
                    Text("\(first.timestamp.formatted(date: .omitted, time: .shortened)) – \(last.timestamp.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(dayData.formattedDistance)
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
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.systemGray6)))
    }
}
