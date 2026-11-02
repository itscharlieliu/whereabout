# Whereabout

Whereabout is a private, on-device location journal for iPhone.

It runs quietly in the background and helps you look back on your day: where you went, how long you stayed, and how you got there. No accounts, no cloud sync, no third-party backend — your history stays on your device.

## App Store

[Download Whereabout on the App Store](https://apps.apple.com/us/app/whereabout-location-log/id6760775197)

## What it does

- Automatically records your movement throughout the day
- Detects visits to places you stop at
- Draws your route on a map
- Shows a timeline of places visited and travel between them
- Reverse geocodes visits into readable place names and addresses
- Lets you browse previous days of location history
- Tracks useful daily stats like places visited, route points, and distance traveled
- Supports background tracking with battery-conscious location updates
- Keeps all app data stored locally on-device

## Privacy

Whereabout is designed to be private by default.

- No account required
- No cloud backend
- No third-party analytics
- No data sold or shared
- Data is stored locally on your device

## Tech stack

- SwiftUI
- SwiftData
- CoreLocation
- MapKit

## How it works

Whereabout combines two iOS location systems:

- **Significant location changes** to capture movement in a battery-friendly way
- **Visit monitoring** to detect places where you arrived and stayed for a while

Those records are stored locally and rendered as:

- a daily route map
- a timeline of visits and travel segments
- lightweight day-level stats

## Project structure

```text
Whereabout/
├── Models/        # SwiftData models for locations and visits
├── Services/      # CoreLocation tracking and geocoding
├── Views/         # SwiftUI screens, timeline, and map UI
└── WhereaboutApp.swift
```

For a deeper walkthrough, see [ARCHITECTURE.md](./ARCHITECTURE.md).

## iPhone Duo

Whereabout adapts by size class, not by device or orientation:

- **Folded (outer display, 466 × 678 pt, compact width):** the usual stacked layout — map on top, stats, then the timeline.
- **Unfolded (inner display, 669 × 951 pt, regular width in both orientations):** a side-by-side layout — map on the left, stats and timeline on the right. Tapping a visit still recentres the map.
- **Folded landscape (compact height):** the map shrinks from 300 pt to 180 pt so the timeline still gets room.

The inner display ignores `supportedInterfaceOrientations`, and the same window can shrink to a compact pane in Split View, so no layout decision in the app checks device, idiom, orientation, or screen size. Navigation and toolbar items use SwiftUI `.toolbar` inside a `NavigationStack`, so the system can move them to the vertical bar on the inner display. To get the full edge-to-edge inner display, build with the iOS 27.1 SDK (Xcode 27.1+); the deployment target stays iOS 26.

## Development

### Requirements

- Xcode 27.1+ for full iPhone Duo inner-display support
- iOS 26+ (the project's deployment target)
- Location permissions enabled (Always permission is best for background tracking)

### Build

```bash
# Simulator build
xcodebuild -project Whereabout.xcodeproj -scheme Whereabout -sdk iphonesimulator -configuration Debug build

# Device build
xcodebuild -project Whereabout.xcodeproj -scheme Whereabout -sdk iphoneos -configuration Release build
```

## Why this exists

A lot of location-history products either push your data to the cloud, make privacy a second-class feature, or bury the useful part of the experience behind maps with no real day-by-day journal.

Whereabout is intentionally simple: open the app, pick a day, and see your route and stops.
