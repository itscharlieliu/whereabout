import SwiftUI
import MapKit

struct WhereaboutMapView: View {
    let dayData: DayData
    var selectedVisit: VisitRecord? = nil

    @State private var position: MapCameraPosition = .automatic

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

            // Start and end markers for route
            if let first = dayData.locations.first {
                Annotation("Start", coordinate: first.coordinate, anchor: .bottom) {
                    Image(systemName: "flag.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.green)
                }
            }
            if dayData.locations.count > 1, let last = dayData.locations.last {
                Annotation("Latest", coordinate: last.coordinate, anchor: .bottom) {
                    Image(systemName: "flag.checkered.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.orange)
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
        .onChange(of: selectedVisit?.persistentModelID) { _, _ in
            guard let visit = selectedVisit else { return }
            withAnimation {
                position = .region(MKCoordinateRegion(
                    center: visit.coordinate,
                    latitudinalMeters: 500,
                    longitudinalMeters: 500
                ))
            }
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
