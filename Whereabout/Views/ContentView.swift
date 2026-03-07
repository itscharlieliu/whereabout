import SwiftUI
import SwiftData

struct ContentView: View {
    @StateObject private var locationManager = LocationManager.shared
    @Environment(\.modelContext) private var modelContext

    @State private var selectedDate = Date()
    @State private var showDatePicker = false
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Date navigation bar
                dateNavigationBar

                Divider()

                // Whereabout content
                WhereaboutView(selectedDate: selectedDate)
            }
            .navigationTitle("Whereabout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        selectedDate = Date()
                    } label: {
                        Text("Today")
                            .fontWeight(.medium)
                    }
                    .disabled(Calendar.current.isDateInToday(selectedDate))
                }
            }
            .sheet(isPresented: $showDatePicker) {
                datePickerSheet
            }
            .sheet(isPresented: $showSettings) {
                settingsSheet
            }
            .onAppear {
                locationManager.modelContainer = modelContext.container
                if locationManager.authorizationStatus == .notDetermined {
                    locationManager.requestPermission()
                } else if locationManager.authorizationStatus == .authorizedAlways ||
                          locationManager.authorizationStatus == .authorizedWhenInUse {
                    if !locationManager.isTracking {
                        locationManager.startTracking()
                    }
                }
            }
        }
    }

    // MARK: - Date Navigation

    private var dateNavigationBar: some View {
        HStack {
            Button {
                withAnimation {
                    selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title3)
                    .fontWeight(.semibold)
            }

            Spacer()

            Button {
                showDatePicker = true
            } label: {
                VStack(spacing: 2) {
                    Text(dayLabel)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text(selectedDate.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(.primary)

            Spacer()

            Button {
                withAnimation {
                    selectedDate = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.title3)
                    .fontWeight(.semibold)
            }
            .disabled(Calendar.current.isDateInToday(selectedDate))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
    }

    private var dayLabel: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(selectedDate) {
            return "Today"
        } else if calendar.isDateInYesterday(selectedDate) {
            return "Yesterday"
        } else {
            return selectedDate.formatted(.dateTime.weekday(.wide))
        }
    }

    // MARK: - Date Picker Sheet

    private var datePickerSheet: some View {
        NavigationStack {
            VStack {
                DatePicker(
                    "Select Date",
                    selection: $selectedDate,
                    in: ...Date(),
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .padding()

                Spacer()
            }
            .navigationTitle("Pick a Date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        showDatePicker = false
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Settings Sheet

    private var settingsSheet: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Label("Tracking", systemImage: "location.fill")
                        Spacer()
                        if locationManager.isTracking {
                            Text("Active")
                                .foregroundStyle(.green)
                                .fontWeight(.medium)
                        } else {
                            Text("Inactive")
                                .foregroundStyle(.red)
                                .fontWeight(.medium)
                        }
                    }

                    HStack {
                        Label("Permission", systemImage: "lock.shield")
                        Spacer()
                        Text(permissionLabel)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Location")
                }

                Section {
                    Button {
                        if locationManager.isTracking {
                            locationManager.stopTracking()
                        } else {
                            locationManager.startTracking()
                        }
                    } label: {
                        Label(
                            locationManager.isTracking ? "Stop Tracking" : "Start Tracking",
                            systemImage: locationManager.isTracking ? "pause.circle" : "play.circle"
                        )
                    }

                    if locationManager.authorizationStatus != .authorizedAlways {
                        Button {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            Label("Open Location Settings", systemImage: "gear")
                        }
                    }
                } header: {
                    Text("Controls")
                }

                Section {
                    Button(role: .destructive) {
                        clearAllData()
                    } label: {
                        Label("Delete All Data", systemImage: "trash")
                    }
                } header: {
                    Text("Data")
                } footer: {
                    Text("All location data is stored locally on your device and is never sent to any server.")
                }

                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("About")
                } footer: {
                    Text("Whereabout tracks your location throughout the day so you can revisit where you've been. All data stays on your device.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        showSettings = false
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private var permissionLabel: String {
        switch locationManager.authorizationStatus {
        case .authorizedAlways: return "Always"
        case .authorizedWhenInUse: return "When In Use"
        case .denied: return "Denied"
        case .restricted: return "Restricted"
        case .notDetermined: return "Not Set"
        @unknown default: return "Unknown"
        }
    }

    private func clearAllData() {
        do {
            try modelContext.delete(model: LocationRecord.self)
            try modelContext.delete(model: VisitRecord.self)
            try modelContext.save()
        } catch {
            print("Failed to delete data: \(error)")
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .modelContainer(for: [LocationRecord.self, VisitRecord.self], inMemory: true)
    }
}
