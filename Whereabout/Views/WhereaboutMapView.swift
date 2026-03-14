import SwiftUI
import MapKit

struct WhereaboutMapView: View {
    let dayData: DayData
    var selectedVisit: VisitRecord? = nil

    @State private var position: MapCameraPosition = .automatic
    @State private var mapMoved = false
    @State private var cameraSettled = false

    var body: some View {
        Map(position: $position) {
            // Route polyline, anchored to the previous day's last location if available.
            let polylineCoords: [CLLocationCoordinate2D] = {
                var coords = dayData.locations.map { $0.coordinate }
                if let prior = dayData.priorLocation { coords.insert(prior.coordinate, at: 0) }
                return coords
            }()
            if polylineCoords.count >= 2 {
                MapPolyline(coordinates: polylineCoords)
                    .stroke(.blue, lineWidth: 3)
            }

            // Visit annotations
            ForEach(dayData.filteredVisits) { item in
                let visit = item.visit
                Annotation(
                    visit.placeName ?? "Visit",
                    coordinate: visit.coordinate,
                    anchor: .bottom
                ) {
                    VStack(spacing: 2) {
                        Image(systemName: visit.isOngoing ? "location.fill" : "mappin.circle.fill")
                            .font(.title2)
                            .foregroundStyle(visit.isOngoing ? .green : .red)
                            .background(
                                Circle()
                                    .fill(.white)
                                    .frame(width: 24, height: 24)
                            )
                    }
                }
            }

        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .including([
            .cafe, .restaurant, .store, .hotel, .airport, .publicTransport
        ])))
        .mapControls {
            MapCompass()
            MapScaleView()
            MapUserLocationButton()
        }
        .overlay(alignment: .topLeading) {
            if mapMoved {
                Button {
                    mapMoved = false
                    settleCamera()
                    if let region = contentRegion {
                        withAnimation { position = .region(region) }
                    }
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.blue)
                        .frame(width: 44, height: 44)
                        .background(Color(.systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
                }
                .padding(.top, 8)
                .padding(.leading, 8)
                .transition(.opacity)
            }
        }
        .onAppear { settleCamera() }
        .onMapCameraChange {
            guard cameraSettled else { return }
            withAnimation { mapMoved = true }
        }
        .onChange(of: selectedVisit?.persistentModelID) { _, _ in
            guard let visit = selectedVisit else { return }
            settleCamera()
            withAnimation {
                position = .region(MKCoordinateRegion(
                    center: visit.coordinate,
                    latitudinalMeters: 500,
                    longitudinalMeters: 500
                ))
            }
        }
    }

    /// Bounding region that fits all of the day's locations and visits.
    private var contentRegion: MKCoordinateRegion? {
        var coords: [CLLocationCoordinate2D] = dayData.locations.map(\.coordinate)
        coords += dayData.filteredVisits.map(\.visit.coordinate)
        if let prior = dayData.priorLocation { coords.append(prior.coordinate) }
        guard !coords.isEmpty else { return nil }

        let lats = coords.map(\.latitude)
        let lons = coords.map(\.longitude)
        let minLat = lats.min()!, maxLat = lats.max()!
        let minLon = lons.min()!, maxLon = lons.max()!

        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (minLat + maxLat) / 2,
                longitude: (minLon + maxLon) / 2
            ),
            span: MKCoordinateSpan(
                latitudeDelta: max(maxLat - minLat, 0.005) * 1.4,
                longitudeDelta: max(maxLon - minLon, 0.005) * 1.4
            )
        )
    }

    /// Marks the camera as settling so the next camera changes (from automatic
    /// positioning or programmatic moves) are ignored. Re-enables tracking after
    /// a short delay once the map has finished animating.
    private func settleCamera() {
        cameraSettled = false
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            cameraSettled = true
        }
    }
}

struct WhereaboutMapView_Previews: PreviewProvider {
    static var previews: some View {
        WhereaboutMapView(dayData: DayData.build(
            locations: [],
            visits: [],
            priorLocation: LocationRecord?.none,
            priorVisit: VisitRecord?.none
        ))
    }
}
