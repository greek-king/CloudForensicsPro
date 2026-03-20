// Models/ForensicsModels.swift
import Foundation
import SwiftUI

// MARK: - Cloud Provider
enum CloudProvider: String, CaseIterable, Codable, Identifiable {
    case iCloud    = "iCloud"
    case googleDrive = "Google Drive"
    case dropbox   = "Dropbox"
    case oneDrive  = "OneDrive"
    case box       = "Box"
    case unknown   = "Unknown"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .iCloud:      return "icloud.fill"
        case .googleDrive: return "externaldrive.fill.badge.wifi"
        case .dropbox:     return "archivebox.fill"
        case .oneDrive:    return "cloud.fill"
        case .box:         return "shippingbox.fill"
        case .unknown:     return "questionmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .iCloud:      return Color(hex: "#147EFB")
        case .googleDrive: return Color(hex: "#34A853")
        case .dropbox:     return Color(hex: "#0061FF")
        case .oneDrive:    return Color(hex: "#0078D4")
        case .box:         return Color(hex: "#0061D5")
        case .unknown:     return Color(hex: "#8E8E93")
        }
    }
}

// MARK: - File Event Type
enum FileEventType: String, Codable {
    case created    = "Created"
    case modified   = "Modified"
    case deleted    = "Deleted"
    case accessed   = "Accessed"
    case moved      = "Moved"
    case shared     = "Shared"
    case downloaded = "Downloaded"
    case uploaded   = "Uploaded"
    case restored   = "Restored"
    case renamed    = "Renamed"

    var icon: String {
        switch self {
        case .created:    return "plus.circle.fill"
        case .modified:   return "pencil.circle.fill"
        case .deleted:    return "minus.circle.fill"
        case .accessed:   return "eye.circle.fill"
        case .moved:      return "arrow.right.circle.fill"
        case .shared:     return "person.2.circle.fill"
        case .downloaded: return "arrow.down.circle.fill"
        case .uploaded:   return "arrow.up.circle.fill"
        case .restored:   return "arrow.counterclockwise.circle.fill"
        case .renamed:    return "character.cursor.ibeam"
        }
    }

    var color: Color {
        switch self {
        case .created:    return Color(hex: "#34C759")
        case .modified:   return Color(hex: "#FF9500")
        case .deleted:    return Color(hex: "#FF3B30")
        case .accessed:   return Color(hex: "#147EFB")
        case .moved:      return Color(hex: "#AF52DE")
        case .shared:     return Color(hex: "#FF2D55")
        case .downloaded: return Color(hex: "#5AC8FA")
        case .uploaded:   return Color(hex: "#30B0C7")
        case .restored:   return Color(hex: "#34C759")
        case .renamed:    return Color(hex: "#FFCC00")
        }
    }

    var severity: EventSeverity {
        switch self {
        case .deleted, .shared:            return .high
        case .downloaded, .modified:       return .medium
        case .created, .uploaded:          return .low
        default:                           return .info
        }
    }
}

// MARK: - Event Severity
enum EventSeverity: Int, Codable, Comparable {
    case info   = 0
    case low    = 1
    case medium = 2
    case high   = 3

    static func < (lhs: EventSeverity, rhs: EventSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var label: String {
        switch self {
        case .info:   return "Info"
        case .low:    return "Low"
        case .medium: return "Medium"
        case .high:   return "High"
        }
    }

    var color: Color {
        switch self {
        case .info:   return Color(hex: "#8E8E93")
        case .low:    return Color(hex: "#34C759")
        case .medium: return Color(hex: "#FF9500")
        case .high:   return Color(hex: "#FF3B30")
        }
    }
}

// MARK: - File Event (core forensics record)
struct FileEvent: Identifiable, Codable {
    let id: UUID
    let provider: CloudProvider
    let eventType: FileEventType
    let fileName: String
    let filePath: String
    let fileSize: Int64?          // bytes
    let timestamp: Date
    let userID: String?
    let ipAddress: String?
    let deviceName: String?
    let deviceOS: String?
    let checksum: String?         // MD5/SHA256 for integrity
    let previousPath: String?     // for moves/renames
    let sharedWith: [String]?     // for share events
    let isAnomaly: Bool
    let anomalyReason: String?
    let rawLogLine: String?       // original log text

    var formattedSize: String {
        guard let size = fileSize else { return "Unknown" }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    var formattedTimestamp: String {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .medium
        return f.string(from: timestamp)
    }

    var relativeTimestamp: String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: timestamp, relativeTo: Date())
    }

    var fileExtension: String {
        (fileName as NSString).pathExtension.lowercased()
    }

    var isSensitiveFile: Bool {
        let sensitiveExtensions = ["pdf", "doc", "docx", "xls", "xlsx",
                                   "key", "p12", "pem", "pfx", "cert",
                                   "sql", "db", "sqlite", "bak", "zip",
                                   "rar", "7z", "tar", "gz"]
        return sensitiveExtensions.contains(fileExtension)
    }
}

// MARK: - Investigation Case
struct ForensicsCase: Identifiable, Codable {
    let id: UUID
    var name: String
    var description: String
    var createdAt: Date
    var providers: [CloudProvider]
    var events: [FileEvent]
    var findings: [Finding]
    var status: CaseStatus
    var tags: [String]

    var totalEvents: Int { events.count }
    var anomalyCount: Int { events.filter { $0.isAnomaly }.count }
    var deletedCount: Int { events.filter { $0.eventType == .deleted }.count }
    var sharedCount:  Int { events.filter { $0.eventType == .shared }.count }

    var riskScore: Int {
        let base = anomalyCount * 20 + deletedCount * 5 + sharedCount * 10
        return min(100, base)
    }

    var riskLevel: EventSeverity {
        switch riskScore {
        case 0..<25:  return .low
        case 25..<60: return .medium
        default:      return .high
        }
    }

    var dateRange: String {
        guard let first = events.min(by: { $0.timestamp < $1.timestamp })?.timestamp,
              let last  = events.max(by: { $0.timestamp < $1.timestamp })?.timestamp else {
            return "No events"
        }
        let f = DateFormatter()
        f.dateStyle = .short
        return "\(f.string(from: first)) – \(f.string(from: last))"
    }

    enum CaseStatus: String, Codable {
        case active   = "Active"
        case closed   = "Closed"
        case archived = "Archived"
    }
}

// MARK: - Finding
struct Finding: Identifiable, Codable {
    let id: UUID
    let title: String
    let description: String
    let severity: EventSeverity
    let relatedEventIDs: [UUID]
    let timestamp: Date
    let category: FindingCategory

    enum FindingCategory: String, Codable {
        case exfiltration   = "Data Exfiltration"
        case deletion       = "Mass Deletion"
        case sharing        = "Unauthorized Sharing"
        case anomaly        = "Anomalous Activity"
        case timing         = "Suspicious Timing"
        case volume         = "Unusual Volume"
        case device         = "Unknown Device"
        case location       = "Suspicious Location"
    }
}

// MARK: - Log Parser Result
struct ParseResult {
    var events: [FileEvent]
    var errors: [String]
    var provider: CloudProvider
    var linesProcessed: Int
    var eventsFound: Int
}

// MARK: - Exfiltration Pattern
struct ExfiltrationPattern {
    var suspectedFiles: [FileEvent]
    var totalSize: Int64
    var timeWindow: TimeInterval
    var destinationIPs: [String]
    var riskScore: Int
    var description: String
}

// MARK: - Timeline Entry (for UI)
struct TimelineEntry: Identifiable {
    let id: UUID
    let date: Date
    let events: [FileEvent]
    var isAnomaly: Bool { events.contains { $0.isAnomaly } }
    var maxSeverity: EventSeverity { events.map { $0.eventType.severity }.max() ?? .info }
}
