# Whereabout Architecture

## Overview

Whereabout is a personal location-tracking iOS app that silently records where you've been throughout the day. All data is stored locally on-device — nothing is sent to a server. Users can browse any past day to see a map of their route and a chronological timeline of the places they visited.

**Tech stack:** SwiftUI · SwiftData · CoreLocation · MapKit · iOS 17+

---

## Project Structure

```
Whereabout/
├── WhereaboutApp.swift          # App entry point
├── Models/
│   └── LocationModels.swift     # SwiftData model classes
├── Services/
│   └── LocationManager.swift    # CoreLocation wrapper / singleton
└── Views/
    ├── ContentView.swift         # Root shell: nav, date picker, settings
    ├── WhereaboutView.swift      # Day view: map + timeline + stats
    └── WhereaboutMapView.swift   # MapKit map with polyline & annotations
```

---

## Data Models (`LocationModels.swift`)

Two SwiftData `@Model` classes persist all location data to disk.

### `LocationRecord`
Represents a single GPS fix captured while the user is moving.

| Field | Type | Description |
|---|---|---|
| `latitude` / `longitude` | `Double` | WGS-84 coordinate |
| `timestamp` | `Date` | When the fix was recorded |
| `altitude` | `Double` | Meters above sea level |
| `speed` | `Double` | m/s, `-1` if unavailable |
| `horizontalAccuracy` | `Double` | Radius of uncertainty in meters |

Computed property: `coordinate: CLLocationCoordinate2D` — convenience accessor for MapKit.

### `VisitRecord`
Represents a place where the user lingered, as detected by iOS's visit monitoring.

| Field | Type | Description |
|---|---|---|
| `latitude` / `longitude` | `Double` | Center of the visited place |
| `arrivalDate` | `Date` | When the user arrived |
| `departureDate` | `Date` | When the user left (`Date.distantFuture` if still there) |
| `horizontalAccuracy` | `Double` | Confidence radius |
| `placeName` | `String?` | Human-readable name from reverse geocoding |
| `address` | `String?` | Street / city / state string from reverse geocoding |

Key computed properties:
- `isOngoing: Bool` — true when `departureDate == .distantFuture`
- `duration: TimeInterval` — live duration for ongoing visits, fixed otherwise
- `formattedDuration`, `formattedArrival`, `formattedDeparture` — display strings

---

## Services (`LocationManager.swift`)

`LocationManager` is a `@MainActor` singleton (`LocationManager.shared`) that owns the entire interaction with CoreLocation.

### Initialisation

```
WhereaboutApp.init()
  └─ Creates ModelContainer
  └─ Assigns container to LocationManager.shared.modelContainer
```

The container reference is needed because `LocationManager` lives outside SwiftUI's environment and must create its own `ModelContext` instances when saving.

### Tracking modes

| Mode | API | Behaviour |
|---|---|---|
| Significant location changes | `startMonitoringSignificantLocationChanges()` | Wakes the app roughly every 500 m of movement; battery-friendly |
| Visit monitoring | `startMonitoringVisits()` | iOS automatically detects arrivals and departures at places |

Both modes work in the background (`allowsBackgroundLocationUpdates = true`).

### Permission flow

1. If status is `.notDetermined`, `requestAlwaysAuthorization()` is called.
2. When status changes to `.authorizedAlways` or `.authorizedWhenInUse`, tracking starts automatically via `locationManagerDidChangeAuthorization`.

### Saving a location (`saveLocation`)

1. Creates a new `ModelContext` from the stored container.
2. Wraps the `CLLocation` in a `LocationRecord`.
3. Inserts and saves — only points with `horizontalAccuracy < 100 m` are accepted (filtered before calling this method).

### Saving a visit (`saveVisit` + `reverseGeocode`)

1. Wraps `CLVisit` in a `VisitRecord` and saves immediately.
2. Kicks off `CLGeocoder.reverseGeocodeLocation` asynchronously.
3. On completion, fetches the record again by its `persistentModelID` in a new context, fills in `placeName` and `address`, then saves again.

### Published state

| Property | Use |
|---|---|
| `authorizationStatus` | Drives the permission label in Settings |
| `isTracking` | Drives the tracking toggle in Settings |
| `lastLocation` | Available for future use (not currently displayed) |

---

## Views

### `WhereaboutApp` — Entry Point

- Constructs the `ModelContainer` for `[LocationRecord, VisitRecord]`.
- Injects it into the SwiftUI environment via `.modelContainer(modelContainer)`.
- Passes it to `LocationManager.shared` so the service can save data.

### `ContentView` — Root Shell

Owns the date navigation state (`selectedDate`) and two modal sheets.

**Date navigation bar** — previous/next day chevrons + a centre button that opens the date-picker sheet. The "today" label is humanised ("Today" / "Yesterday" / weekday name).

**Toolbar** — gear icon (settings sheet) + "Today" shortcut button.

**Settings sheet** — a grouped `List` with:
- Location section: live tracking status + permission level
- Controls section: start/stop tracking toggle + deep-link to iOS Location Settings
- Data section: destructive "Delete All Data" button (calls `modelContext.delete(model:)` for both types)
- About section: version string + privacy note

On appear, `ContentView` ensures the `LocationManager` has the current `modelContainer` and starts tracking if permissions allow.

### `WhereaboutView` — Day View

Receives `selectedDate` and immediately constructs two `@Query` instances scoped to that calendar day:

```swift
// LocationRecord: timestamp in [startOfDay, endOfDay)
// VisitRecord:    arrivalDate < endOfDay AND departureDate >= startOfDay
```

**Layout (top to bottom):**

1. **Map** (`WhereaboutMapView`) — 300 pt tall, rounded corners.
2. **Stats bar** — three `StatBadge` tiles: distance walked, number of places, number of GPS points.
3. **Timeline list** or **empty state**.

**Timeline logic:**

```
dayVisits sorted by arrivalDate
  [0]  visitRow(visit[0])
       travelSegment(visit[0] → visit[1])
  [1]  visitRow(visit[1])
       travelSegment(visit[1] → visit[2])
  ...
```

If there are GPS points but no visits, a single "Route recorded" row is shown instead.

`travelSegment` computes straight-line distance and elapsed time between consecutive visits and renders them as small connectors in the timeline.

### `WhereaboutMapView` — Map

A SwiftUI `Map` with:
- **Blue polyline** connecting all `LocationRecord` coordinates in order.
- **Annotation per visit** — green `location.fill` if ongoing, red `mappin.circle.fill` otherwise.
- **Start flag** (green) at the first `LocationRecord`.
- **Latest flag** (orange) at the last `LocationRecord`.
- Standard map style showing cafes, restaurants, transport, etc.
- Map controls: compass, scale bar, user location button.

---

## Data Flow

```
iOS (CoreLocation)
  │  CLLocation events (significant-change)
  │  CLVisit events (arrival / departure)
  ▼
LocationManager (singleton)
  │  filter accuracy < 100 m
  │  create ModelContext
  │  insert LocationRecord / VisitRecord
  │  save()
  │  async: CLGeocoder → update placeName / address → save()
  ▼
SwiftData store (on-device SQLite)
  ▼
@Query (in WhereaboutView, re-evaluated on any store change)
  ▼
WhereaboutView / WhereaboutMapView (re-render)
```

---

## Key Design Decisions

- **Significant location changes** instead of continuous GPS — preserves battery; ~500 m granularity is sufficient for a day-history view.
- **CLVisit monitoring** for place detection — iOS handles the dwell-detection heuristics; no custom logic needed.
- **Per-save `ModelContext`** — `LocationManager` sits outside SwiftUI, so it creates a fresh context each time rather than sharing one across threads.
- **Reverse geocoding is fire-and-forget** — the visit is saved immediately with no address; the geocoder fills it in whenever it resolves. Views will update reactively via `@Query`.
- **All data on-device** — no accounts, no sync, no network requests beyond reverse geocoding.
