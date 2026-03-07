import SwiftUI
import SwiftData

@main
struct TimelineApp: App {
    let modelContainer: ModelContainer

    init() {
        do {
            let schema = Schema([LocationRecord.self, VisitRecord.self])
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            modelContainer = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }

        // Configure the shared location manager with the container
        let container = modelContainer
        Task { @MainActor in
            LocationManager.shared.modelContainer = container
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(modelContainer)
    }
}
