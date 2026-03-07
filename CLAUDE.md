# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

This is an iOS app built with Xcode. Use the following commands:

```bash
# Build for simulator
xcodebuild -project Whereabout.xcodeproj -scheme Whereabout -sdk iphonesimulator -configuration Debug build

# Build for device
xcodebuild -project Whereabout.xcodeproj -scheme Whereabout -sdk iphoneos -configuration Release build

# Run tests (if added)
xcodebuild -project Whereabout.xcodeproj -scheme Whereabout -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 15' test
```

## Architecture

Whereabout is a personal location tracking iOS app that records where the user has been throughout the day. All data is stored locally on-device using SwiftData.

### Key Components

- **WhereaboutApp.swift** - App entry point; initializes SwiftData ModelContainer with `LocationRecord` and `VisitRecord` schemas and configures the shared LocationManager
- **LocationManager** (`Services/LocationManager.swift`) - Singleton that wraps CLLocationManager for background location tracking and visit monitoring. Handles permissions, saves location/visit data to SwiftData, and performs reverse geocoding for visit place names
- **LocationModels.swift** (`Models/`) - SwiftData `@Model` classes:
  - `LocationRecord` - GPS coordinate points with timestamp, altitude, speed, accuracy
  - `VisitRecord` - Places where user stayed, with arrival/departure times and reverse-geocoded address

### Data Flow

1. LocationManager receives CLLocation updates and CLVisit events from iOS
2. Data is filtered (accuracy < 100m for locations) and saved to SwiftData
3. Views use `@Query` with date predicates to fetch and display day-specific data
4. VisitRecord entries are enriched asynchronously via CLGeocoder reverse geocoding

### Views

- **ContentView** - Main navigation with date picker, settings sheet, and tracking controls
- **WhereaboutView** - Day view showing map + timeline list of visits/travel segments with stats (distance, places, points)
- **WhereaboutMapView** - MapKit view displaying route polyline and visit annotations

## Requirements

- iOS 17.0+
- Xcode 15.4+
- Location permissions: "Always" recommended for background tracking
- Uses SwiftUI, SwiftData, MapKit, CoreLocation
