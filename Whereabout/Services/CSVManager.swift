import Foundation
import SwiftData

struct ImportResult {
    let locations: Int
    let visits: Int
    let skipped: Int
}

enum CSVError: Error, LocalizedError {
    case emptyFile
    case unrecognizedFormat

    var errorDescription: String? {
        switch self {
        case .emptyFile: return "The CSV file is empty."
        case .unrecognizedFormat: return "The CSV file format was not recognized."
        }
    }
}

final class CSVManager {
    static let shared = CSVManager()
    private init() {}

    private let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    // MARK: - Export

    func exportLocations(context: ModelContext) throws -> URL {
        let descriptor = FetchDescriptor<LocationRecord>(
            sortBy: [SortDescriptor(\.timestamp)]
        )
        let records = try context.fetch(descriptor)

        var lines = ["latitude,longitude,timestamp,altitude,speed,horizontalAccuracy"]
        for r in records {
            lines.append("\(r.latitude),\(r.longitude),\(iso8601.string(from: r.timestamp)),\(r.altitude),\(r.speed),\(r.horizontalAccuracy)")
        }

        let content = lines.joined(separator: "\n")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("whereabout_locations.csv")
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func exportVisits(context: ModelContext) throws -> URL {
        let descriptor = FetchDescriptor<VisitRecord>(
            sortBy: [SortDescriptor(\.arrivalDate)]
        )
        let records = try context.fetch(descriptor)

        var lines = ["latitude,longitude,arrivalDate,departureDate,horizontalAccuracy,placeName,address"]
        for r in records {
            let departure = r.isOngoing ? "" : iso8601.string(from: r.departureDate)
            let line = "\(r.latitude),\(r.longitude),\(iso8601.string(from: r.arrivalDate)),\(departure),\(r.horizontalAccuracy),\(csvField(r.placeName ?? "")),\(csvField(r.address ?? ""))"
            lines.append(line)
        }

        let content = lines.joined(separator: "\n")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("whereabout_visits.csv")
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - Import

    func importCSV(from url: URL, into context: ModelContext) throws -> ImportResult {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        let content = try String(contentsOf: url, encoding: .utf8)
        let lines = content.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        guard let header = lines.first else { throw CSVError.emptyFile }

        let dataLines = Array(lines.dropFirst())

        if header.contains("arrivalDate") {
            let (imported, skipped) = try importVisits(lines: dataLines, into: context)
            return ImportResult(locations: 0, visits: imported, skipped: skipped)
        } else if header.contains("timestamp") {
            let (imported, skipped) = try importLocations(lines: dataLines, into: context)
            return ImportResult(locations: imported, visits: 0, skipped: skipped)
        } else {
            throw CSVError.unrecognizedFormat
        }
    }

    // MARK: - Private importers

    private func importLocations(lines: [String], into context: ModelContext) throws -> (Int, Int) {
        let existingDescriptor = FetchDescriptor<LocationRecord>()
        let existing = try context.fetch(existingDescriptor)
        let existingTimestamps = Set(existing.map { $0.timestamp })

        var imported = 0
        var skipped = 0

        for line in lines {
            let fields = parseCSVLine(line)
            guard fields.count >= 6,
                  let lat = Double(fields[0]),
                  let lon = Double(fields[1]),
                  let ts = iso8601.date(from: fields[2]),
                  let alt = Double(fields[3]),
                  let spd = Double(fields[4]),
                  let acc = Double(fields[5])
            else { continue }

            if existingTimestamps.contains(ts) {
                skipped += 1
                continue
            }

            let record = LocationRecord(
                latitude: lat,
                longitude: lon,
                timestamp: ts,
                altitude: alt,
                speed: spd,
                horizontalAccuracy: acc
            )
            context.insert(record)
            imported += 1
        }

        try context.save()
        return (imported, skipped)
    }

    private func importVisits(lines: [String], into context: ModelContext) throws -> (Int, Int) {
        let existingDescriptor = FetchDescriptor<VisitRecord>()
        let existing = try context.fetch(existingDescriptor)
        let existingArrivals = Set(existing.map { $0.arrivalDate })

        var imported = 0
        var skipped = 0

        for line in lines {
            let fields = parseCSVLine(line)
            guard fields.count >= 5,
                  let lat = Double(fields[0]),
                  let lon = Double(fields[1]),
                  let arrival = iso8601.date(from: fields[2]),
                  let acc = Double(fields[4])
            else { continue }

            let departure = fields[3].isEmpty ? Date.distantFuture : (iso8601.date(from: fields[3]) ?? Date.distantFuture)

            if existingArrivals.contains(arrival) {
                skipped += 1
                continue
            }

            let placeName = fields.count > 5 ? (fields[5].isEmpty ? nil : fields[5]) : nil
            let address = fields.count > 6 ? (fields[6].isEmpty ? nil : fields[6]) : nil

            let record = VisitRecord(
                latitude: lat,
                longitude: lon,
                arrivalDate: arrival,
                departureDate: departure,
                horizontalAccuracy: acc,
                placeName: placeName,
                address: address
            )
            context.insert(record)
            imported += 1
        }

        try context.save()
        return (imported, skipped)
    }

    // MARK: - Helpers

    func csvField(_ s: String) -> String {
        guard s.contains(",") || s.contains("\"") || s.contains("\n") else { return s }
        let escaped = s.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }

    func parseCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        var i = line.startIndex

        while i < line.endIndex {
            let ch = line[i]
            if inQuotes {
                if ch == "\"" {
                    let next = line.index(after: i)
                    if next < line.endIndex && line[next] == "\"" {
                        current.append("\"")
                        i = line.index(after: next)
                        continue
                    } else {
                        inQuotes = false
                    }
                } else {
                    current.append(ch)
                }
            } else {
                if ch == "\"" {
                    inQuotes = true
                } else if ch == "," {
                    fields.append(current)
                    current = ""
                } else {
                    current.append(ch)
                }
            }
            i = line.index(after: i)
        }
        fields.append(current)
        return fields
    }
}
