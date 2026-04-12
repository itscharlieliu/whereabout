import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var locationManager = LocationManager.shared
    @Environment(\.modelContext) private var modelContext

    @State private var scrolledDate: Date? = nil
    @State private var showDatePicker = false
    @State private var showSettings = false
    @State private var exportItem: ExportURL?
    @State private var showImportPicker = false
    @State private var importMessage: String?
    @State private var showImportAlert = false
    @State private var showDeleteConfirmation = false
    @State private var webhookURLText = ""
    @State private var webhookBearerTokenText = ""

    private var today: Date { Calendar.current.startOfDay(for: Date()) }
    private var selectedDate: Date { scrolledDate ?? today }

    /// 730 days ending today, each normalized to start-of-day.
    private var scrollDates: [Date] {
        (0..<730).reversed().compactMap {
            Calendar.current.date(byAdding: .day, value: -$0, to: today)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Date navigation bar
                dateNavigationBar

                if !locationManager.isTracking {
                    HStack(spacing: 6) {
                        Image(systemName: "pause.circle.fill")
                        Text("Tracking paused")
                            .font(.footnote)
                            .fontWeight(.medium)
                        Spacer()
                        Button("Resume") {
                            locationManager.startTracking()
                        }
                        .font(.footnote)
                        .fontWeight(.semibold)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.orange.opacity(0.15))
                    .foregroundStyle(Color.orange)
                }

                Divider()

                // Horizontal paging scroll — one WhereaboutView per day, lazy loaded
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 0) {
                        ForEach(scrollDates, id: \.self) { date in
                            WhereaboutView(selectedDate: date)
                                .containerRelativeFrame(.horizontal)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $scrolledDate)
                .scrollIndicators(.hidden)
                .onAppear { scrolledDate = today }
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
                        scrolledDate = today
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
                    if !locationManager.isTracking && locationManager.trackingEnabledPreference {
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
                scrolledDate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title3)
                    .fontWeight(.semibold)
            }

            Spacer()

            Button {
                showDatePicker = true
            } label: {
                HStack(spacing: 4) {
                    VStack(spacing: 2) {
                        Text(dayLabel)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text(selectedDate.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Image(systemName: "chevron.down")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(.primary)

            Spacer()

            Button {
                scrolledDate = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
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
                    selection: Binding(
                        get: { selectedDate },
                        set: { scrolledDate = Calendar.current.startOfDay(for: $0) }
                    ),
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
                    Button {
                        do {
                            let url = try CSVManager.shared.exportLocations(context: modelContext)
                            exportItem = ExportURL(url: url)
                        } catch {
                            importMessage = "Export failed: \(error.localizedDescription)"
                            showImportAlert = true
                        }
                    } label: {
                        Label("Export Locations CSV", systemImage: "arrow.up.doc.fill")
                    }

                    Button {
                        do {
                            let url = try CSVManager.shared.exportVisits(context: modelContext)
                            exportItem = ExportURL(url: url)
                        } catch {
                            importMessage = "Export failed: \(error.localizedDescription)"
                            showImportAlert = true
                        }
                    } label: {
                        Label("Export Visits CSV", systemImage: "arrow.up.doc.fill")
                    }

                    Button {
                        showImportPicker = true
                    } label: {
                        Label("Import from CSV", systemImage: "arrow.down.doc.fill")
                    }

                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label("Delete All Data", systemImage: "trash")
                    }
                } header: {
                    Text("Data")
                } footer: {
                    Text("All location data is stored locally on your device and is never sent to any server.")
                }

                Section {
                    TextField("https://", text: $webhookURLText)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onChange(of: webhookURLText) { _, newValue in
                            locationManager.webhookURL = newValue
                        }

                    if !webhookURLText.isEmpty {
                        SecureField("Bearer token (optional)", text: $webhookBearerTokenText)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .onChange(of: webhookBearerTokenText) { _, newValue in
                                locationManager.webhookBearerToken = newValue
                            }
                    }

                    Button {
                        if let url = LocationManager.webhookLogURL,
                           FileManager.default.fileExists(atPath: url.path) {
                            exportItem = ExportURL(url: url)
                        } else {
                            importMessage = "No webhook logs yet."
                            showImportAlert = true
                        }
                    } label: {
                        Label("Export Webhook Logs", systemImage: "list.bullet.rectangle")
                    }
                } header: {
                    Text("Webhook")
                } footer: {
                    Text("When set, Whereabout will POST a JSON payload to this URL whenever you arrive at or depart from a location.")
                }

                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.2")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("About")
                } footer: {
                    Text("Whereabout tracks your location throughout the day so you can revisit where you've been. All data stays on your device.")
                }
            }
            .onAppear {
                webhookURLText = locationManager.webhookURL
                webhookBearerTokenText = locationManager.webhookBearerToken
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
            .sheet(item: $exportItem) { item in
                ActivityView(url: item.url)
            }
            .fileImporter(
                isPresented: $showImportPicker,
                allowedContentTypes: [.commaSeparatedText]
            ) { result in
                switch result {
                case .success(let url):
                    do {
                        let importResult = try CSVManager.shared.importCSV(from: url, into: modelContext)
                        let total = importResult.locations + importResult.visits
                        importMessage = "\(total) imported, \(importResult.skipped) skipped"
                    } catch {
                        importMessage = "Import failed: \(error.localizedDescription)"
                    }
                    showImportAlert = true
                case .failure(let error):
                    importMessage = "Could not open file: \(error.localizedDescription)"
                    showImportAlert = true
                }
            }
            .alert("Import Result", isPresented: $showImportAlert) {
                Button("OK") {}
            } message: {
                Text(importMessage ?? "")
            }
            .alert("Delete All Data?", isPresented: $showDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    clearAllData()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete all your location and visit history. This cannot be undone.")
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
            importMessage = "All data deleted successfully."
        } catch {
            importMessage = "Delete failed: \(error.localizedDescription)"
        }
        showImportAlert = true
    }
}

private struct ExportURL: Identifiable {
    let id = UUID()
    let url: URL
}

private struct ActivityView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .modelContainer(for: [LocationRecord.self, VisitRecord.self], inMemory: true)
    }
}
