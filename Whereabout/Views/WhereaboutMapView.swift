import SwiftUI
import MapKit

struct WhereaboutMapView: View {
    let locations: [LocationRecord]
    let visits: [VisitRecord]
    var selectedVisit: VisitRecord? = nil
    var priorLocation: LocationRecord? = nil

    @State private var position: MapCameraPosition = .automatic

    var body: some View {
        Map(position: $position) {
            // Draw route polyline, anchored to previous day's last location if available
            let polylineCoords: [CLLocationCoordinate2D] = {
                var coords = locations.map { $0.coordinate }
                if let prior = priorLocation { coords.insert(prior.coordinate, at: 0) }
                return coords
            }()
            if polylineCoords.count >= 2 {
                MapPolyline(coordinates: polylineCoords)
                    .stroke(.blue, lineWidth: 3)
            }

            // Visit annotations
            ForEach(visits) { visit in
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
            if let first = locations.first {
                Annotation("Start", coordinate: first.coordinate, anchor: .bottom) {
                    Image(systemName: "flag.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.green)
                }
            }
            if locations.count > 1, let last = locations.last {
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
        WhereaboutMapView(locations: [], visits: [])
    }
}
