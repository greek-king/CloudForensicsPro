// Services/LogParser.swift
// Parses cloud sync logs from iCloud, Google Drive, Dropbox, OneDrive
// Each provider has its own log format — this engine handles all of them

import Foundation

class LogParser {

    // MARK: - Main Parse Entry Point

    func parse(text: String, provider: CloudProvider) -> ParseResult {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var events: [FileEvent] = []
        var errors: [String] = []

        for (lineNum, line) in lines.enumerated() {
            do {
                if let event = try parseLine(line, provider: provider) {
                    events.append(event)
                }
            } catch {
                errors.append("Line \(lineNum + 1): \(error.localizedDescription)")
            }
        }

        // Sort by timestamp
        events.sort { $0.timestamp < $1.timestamp }

        // Run anomaly detection
        let analyzed = detectAnomalies(in: events)

        return ParseResult(
            events: analyzed,
            errors: errors,
            provider: provider,
            linesProcessed: lines.count,
            eventsFound: analyzed.count
        )
    }

    // MARK: - Route to Provider Parser

    private func parseLine(_ line: String, provider: CloudProvider) throws -> FileEvent? {
        switch provider {
        case .iCloud:      return try parseICloudLine(line)
        case .googleDrive: return try parseGoogleDriveLine(line)
        case .dropbox:     return try parseDropboxLine(line)
        case .oneDrive:    return try parseOneDriveLine(line)
        case .box:         return try parseBoxLine(line)
        case .unknown:     return try parseGenericLine(line)
        }
    }

    // MARK: - iCloud Log Parser
    // Format: 2024-01-15T14:23:45Z [INFO] CloudDocs: file_op=UPLOAD path=/Documents/report.pdf size=2048000 device=iPhone-14 user=apple@example.com

    private func parseICloudLine(_ line: String) throws -> FileEvent? {
        guard line.contains("CloudDocs") || line.contains("iCloud") || line.contains("UBIQUITY") else {
            return nil
        }

        let timestamp = extractTimestamp(from: line) ?? Date()
        let eventType = extractICloudEventType(from: line)
        let path = extractValue(from: line, key: "path") ?? extractValue(from: line, key: "file") ?? "Unknown"
        let fileName = URL(fileURLWithPath: path).lastPathComponent
        let sizeStr = extractValue(from: line, key: "size")
        let size = sizeStr.flatMap { Int64($0) }
        let device = extractValue(from: line, key: "device") ?? extractValue(from: line, key: "deviceName")
        let user = extractValue(from: line, key: "user") ?? extractValue(from: line, key: "account")
        let ip = extractValue(from: line, key: "ip") ?? extractValue(from: line, key: "src_ip")

        return FileEvent(
            id: UUID(),
            provider: .iCloud,
            eventType: eventType,
            fileName: fileName.isEmpty ? path : fileName,
            filePath: path,
            fileSize: size,
            timestamp: timestamp,
            userID: user,
            ipAddress: ip,
            deviceName: device,
            deviceOS: extractValue(from: line, key: "os"),
            checksum: extractValue(from: line, key: "checksum") ?? extractValue(from: line, key: "hash"),
            previousPath: extractValue(from: line, key: "prev_path") ?? extractValue(from: line, key: "from"),
            sharedWith: nil,
            isAnomaly: false,
            anomalyReason: nil,
            rawLogLine: line
        )
    }

    private func extractICloudEventType(from line: String) -> FileEventType {
        let upper = line.uppercased()
        if upper.contains("UPLOAD") || upper.contains("PUT")       { return .uploaded }
        if upper.contains("DOWNLOAD") || upper.contains("GET")     { return .downloaded }
        if upper.contains("DELETE") || upper.contains("REMOVE")    { return .deleted }
        if upper.contains("MOVE") || upper.contains("RENAME")      { return .moved }
        if upper.contains("SHARE") || upper.contains("COLLAB")     { return .shared }
        if upper.contains("CREATE") || upper.contains("NEW")       { return .created }
        if upper.contains("MODIFY") || upper.contains("EDIT")      { return .modified }
        if upper.contains("ACCESS") || upper.contains("READ")      { return .accessed }
        if upper.contains("RESTORE") || upper.contains("RECOVER")  { return .restored }
        return .accessed
    }

    // MARK: - Google Drive Log Parser
    // Format: {"time":"2024-01-15T14:23:45.000Z","actor":{"email":"user@gmail.com"},"events":[{"type":"access","name":"view","parameters":[{"name":"doc_title","value":"Report.pdf"},{"name":"owner","value":"owner@gmail.com"}]}]}

    private func parseGoogleDriveLine(_ line: String) throws -> FileEvent? {
        // Try JSON first
        if line.hasPrefix("{"), let data = line.data(using: .utf8) {
            return try parseGoogleDriveJSON(data)
        }
        // Fall back to key=value
        guard line.contains("drive") || line.contains("doc") || line.contains("gdoc") else { return nil }
        return try parseGenericLine(line, overrideProvider: .googleDrive)
    }

    private func parseGoogleDriveJSON(_ data: Data) throws -> FileEvent? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        let timeStr = json["time"] as? String ?? json["timestamp"] as? String ?? ""
        let timestamp = parseISO8601(timeStr) ?? Date()

        let actor = json["actor"] as? [String: Any]
        let email = actor?["email"] as? String ?? actor?["profileId"] as? String

        let events = (json["events"] as? [[String: Any]])?.first
        let eventName = events?["name"] as? String ?? events?["type"] as? String ?? "access"

        var fileName = "Unknown"
        var filePath = "/"
        var fileSize: Int64? = nil

        if let params = events?["parameters"] as? [[String: Any]] {
            for param in params {
                let name = param["name"] as? String ?? ""
                let value = param["value"] as? String ?? ""
                switch name {
                case "doc_title", "file_name":   fileName = value
                case "doc_id", "file_id":        filePath = "/\(value)"
                case "file_size":                fileSize = Int64(value)
                case "owner":                    break
                default: break
                }
            }
        }

        let eventType = mapGoogleEventName(eventName)

        return FileEvent(
            id: UUID(),
            provider: .googleDrive,
            eventType: eventType,
            fileName: fileName,
            filePath: filePath,
            fileSize: fileSize,
            timestamp: timestamp,
            userID: email,
            ipAddress: json["ipAddress"] as? String,
            deviceName: nil,
            deviceOS: nil,
            checksum: nil,
            previousPath: nil,
            sharedWith: nil,
            isAnomaly: false,
            anomalyReason: nil,
            rawLogLine: String(data: data, encoding: .utf8)
        )
    }

    private func mapGoogleEventName(_ name: String) -> FileEventType {
        switch name.lowercased() {
        case "view", "access", "preview":     return .accessed
        case "edit", "change", "update":      return .modified
        case "create", "add", "new":          return .created
        case "delete", "trash", "remove":     return .deleted
        case "download":                      return .downloaded
        case "upload":                        return .uploaded
        case "move":                          return .moved
        case "rename":                        return .renamed
        case "share", "acl_change":           return .shared
        case "restore", "untrash":            return .restored
        default:                              return .accessed
        }
    }

    // MARK: - Dropbox Log Parser
    // Format: 2024-01-15 14:23:45 +0000 | user@email.com | file_ops.upload | /Documents/report.pdf | 2048000 bytes | 192.168.1.1

    private func parseDropboxLine(_ line: String) throws -> FileEvent? {
        guard line.contains("|") || line.contains("dropbox") || line.contains("file_ops") else { return nil }

        if line.contains("|") {
            let parts = line.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count >= 3 else { return nil }

            let timestamp = parseFlexibleDate(parts[0]) ?? Date()
            let user = parts.count > 1 ? parts[1] : nil
            let action = parts.count > 2 ? parts[2] : ""
            let path = parts.count > 3 ? parts[3] : "Unknown"
            let fileName = URL(fileURLWithPath: path).lastPathComponent
            let sizeStr = parts.count > 4 ? parts[4].components(separatedBy: " ").first : nil
            let size = sizeStr.flatMap { Int64($0) }
            let ip = parts.count > 5 ? parts[5] : nil

            return FileEvent(
                id: UUID(),
                provider: .dropbox,
                eventType: mapDropboxAction(action),
                fileName: fileName.isEmpty ? path : fileName,
                filePath: path,
                fileSize: size,
                timestamp: timestamp,
                userID: user,
                ipAddress: ip,
                deviceName: parts.count > 6 ? parts[6] : nil,
                deviceOS: nil,
                checksum: nil,
                previousPath: nil,
                sharedWith: nil,
                isAnomaly: false,
                anomalyReason: nil,
                rawLogLine: line
            )
        }
        return try parseGenericLine(line, overrideProvider: .dropbox)
    }

    private func mapDropboxAction(_ action: String) -> FileEventType {
        let a = action.lowercased()
        if a.contains("upload")   { return .uploaded }
        if a.contains("download") { return .downloaded }
        if a.contains("delete")   { return .deleted }
        if a.contains("move")     { return .moved }
        if a.contains("share")    { return .shared }
        if a.contains("create")   { return .created }
        if a.contains("edit")     { return .modified }
        if a.contains("restore")  { return .restored }
        return .accessed
    }

    // MARK: - OneDrive Log Parser
    // Format: 2024-01-15T14:23:45Z,UserPrincipalName,user@company.com,Operation,FileUploaded,FileName,report.pdf,FilePath,/Documents/,FileSize,2048000

    private func parseOneDriveLine(_ line: String) throws -> FileEvent? {
        guard line.contains("OneDrive") || line.contains("SharePoint") ||
              line.contains("FileUploaded") || line.contains("FileDeleted") else { return nil }

        let parts = line.components(separatedBy: ",")
        var dict: [String: String] = [:]

        // Parse as key-value pairs (every even index is key, odd is value)
        var i = 0
        while i + 1 < parts.count {
            dict[parts[i].trimmingCharacters(in: .whitespaces)] =
                parts[i+1].trimmingCharacters(in: .whitespaces)
            i += 2
        }

        let timestamp = parseISO8601(dict["CreationTime"] ?? parts.first ?? "") ?? Date()
        let operation = dict["Operation"] ?? dict["Activity"] ?? ""
        let fileName = dict["FileName"] ?? dict["ItemName"] ?? "Unknown"
        let filePath = dict["FilePath"] ?? dict["RelativeUrl"] ?? "/"
        let user = dict["UserPrincipalName"] ?? dict["UserId"]
        let ip = dict["ClientIP"] ?? dict["IpAddress"]
        let sizeStr = dict["FileSize"] ?? dict["FileSizeBytes"]
        let size = sizeStr.flatMap { Int64($0) }

        return FileEvent(
            id: UUID(),
            provider: .oneDrive,
            eventType: mapOneDriveOperation(operation),
            fileName: fileName,
            filePath: filePath,
            fileSize: size,
            timestamp: timestamp,
            userID: user,
            ipAddress: ip,
            deviceName: dict["DeviceName"],
            deviceOS: dict["DeviceOS"],
            checksum: dict["DocumentId"],
            previousPath: nil,
            sharedWith: nil,
            isAnomaly: false,
            anomalyReason: nil,
            rawLogLine: line
        )
    }

    private func mapOneDriveOperation(_ op: String) -> FileEventType {
        switch op {
        case "FileUploaded":              return .uploaded
        case "FileDownloaded":            return .downloaded
        case "FileDeleted", "FileRecycled": return .deleted
        case "FileMoved":                 return .moved
        case "FileRenamed":               return .renamed
        case "FileCreated":               return .created
        case "FileModified", "FileVersionsAllDeleted": return .modified
        case "SharingSet", "AnonymousLinkCreated": return .shared
        case "FileRestored":              return .restored
        default:                          return .accessed
        }
    }

    // MARK: - Box Log Parser

    private func parseBoxLine(_ line: String) throws -> FileEvent? {
        guard line.contains("box") || line.contains("UPLOAD") || line.contains("DOWNLOAD") else { return nil }
        return try parseGenericLine(line, overrideProvider: .box)
    }

    // MARK: - Generic / Fallback Parser

    private func parseGenericLine(_ line: String, overrideProvider: CloudProvider? = nil) throws -> FileEvent? {
        guard !line.isEmpty, line.count > 10 else { return nil }

        let timestamp = extractTimestamp(from: line) ?? Date()
        let eventType = extractICloudEventType(from: line)
        let path = extractValue(from: line, key: "path") ??
                   extractValue(from: line, key: "file") ??
                   extractValue(from: line, key: "filename") ??
                   extractFilenameFromLine(line) ?? "Unknown"
        let fileName = URL(fileURLWithPath: path).lastPathComponent

        return FileEvent(
            id: UUID(),
            provider: overrideProvider ?? .unknown,
            eventType: eventType,
            fileName: fileName.isEmpty ? path : fileName,
            filePath: path,
            fileSize: extractValue(from: line, key: "size").flatMap { Int64($0) },
            timestamp: timestamp,
            userID: extractValue(from: line, key: "user") ?? extractValue(from: line, key: "email"),
            ipAddress: extractIPAddress(from: line),
            deviceName: extractValue(from: line, key: "device"),
            deviceOS: extractValue(from: line, key: "os"),
            checksum: extractValue(from: line, key: "hash") ?? extractValue(from: line, key: "md5"),
            previousPath: extractValue(from: line, key: "from") ?? extractValue(from: line, key: "prev"),
            sharedWith: nil,
            isAnomaly: false,
            anomalyReason: nil,
            rawLogLine: line
        )
    }

    // MARK: - Anomaly Detection Engine

    func detectAnomalies(in events: [FileEvent]) -> [FileEvent] {
        var result = events
        let calendar = Calendar.current

        // 1. Mass deletion detection (>10 deletes in 1 hour)
        let deletions = events.filter { $0.eventType == .deleted }
        for deletion in deletions {
            let window = events.filter {
                $0.eventType == .deleted &&
                abs($0.timestamp.timeIntervalSince(deletion.timestamp)) < 3600
            }
            if window.count > 10 {
                if let i = result.firstIndex(where: { $0.id == deletion.id }) {
                    result[i] = flagAnomaly(result[i], reason: "Mass deletion: \(window.count) files deleted within 1 hour")
                }
            }
        }

        // 2. Off-hours activity (11pm - 5am)
        for event in events {
            let hour = calendar.component(.hour, from: event.timestamp)
            if hour >= 23 || hour < 5 {
                if let i = result.firstIndex(where: { $0.id == event.id }) {
                    result[i] = flagAnomaly(result[i], reason: "Off-hours activity at \(hour):00")
                }
            }
        }

        // 3. Sensitive file access/deletion
        for event in events where event.isSensitiveFile {
            if event.eventType == .deleted || event.eventType == .downloaded || event.eventType == .shared {
                if let i = result.firstIndex(where: { $0.id == event.id }) {
                    result[i] = flagAnomaly(result[i], reason: "Sensitive file \(event.eventType.rawValue.lowercased()): \(event.fileExtension.uppercased()) file")
                }
            }
        }

        // 4. Bulk download (>20 downloads in 30 min)
        let downloads = events.filter { $0.eventType == .downloaded }
        for download in downloads {
            let window = events.filter {
                $0.eventType == .downloaded &&
                abs($0.timestamp.timeIntervalSince(download.timestamp)) < 1800
            }
            if window.count > 20 {
                if let i = result.firstIndex(where: { $0.id == download.id }) {
                    result[i] = flagAnomaly(result[i], reason: "Bulk download: \(window.count) files in 30 minutes")
                }
            }
        }

        // 5. External IP sharing
        for event in events where event.eventType == .shared {
            if let ip = event.ipAddress, isExternalIP(ip) {
                if let i = result.firstIndex(where: { $0.id == event.id }) {
                    result[i] = flagAnomaly(result[i], reason: "File shared from external IP: \(ip)")
                }
            }
        }

        // 6. Large file exfiltration (>100MB downloads)
        for event in events where event.eventType == .downloaded {
            if let size = event.fileSize, size > 100_000_000 {
                if let i = result.firstIndex(where: { $0.id == event.id }) {
                    result[i] = flagAnomaly(result[i], reason: "Large file downloaded: \(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))")
                }
            }
        }

        return result
    }

    private func flagAnomaly(_ event: FileEvent, reason: String) -> FileEvent {
        FileEvent(
            id: event.id, provider: event.provider, eventType: event.eventType,
            fileName: event.fileName, filePath: event.filePath, fileSize: event.fileSize,
            timestamp: event.timestamp, userID: event.userID, ipAddress: event.ipAddress,
            deviceName: event.deviceName, deviceOS: event.deviceOS, checksum: event.checksum,
            previousPath: event.previousPath, sharedWith: event.sharedWith,
            isAnomaly: true,
            anomalyReason: event.anomalyReason != nil
                ? "\(event.anomalyReason!) | \(reason)"
                : reason,
            rawLogLine: event.rawLogLine
        )
    }

    private func isExternalIP(_ ip: String) -> Bool {
        !ip.hasPrefix("192.168.") && !ip.hasPrefix("10.") &&
        !ip.hasPrefix("172.16.") && ip != "127.0.0.1" && ip != "localhost"
    }

    // MARK: - Exfiltration Analysis

    func detectExfiltration(in events: [FileEvent]) -> [ExfiltrationPattern] {
        var patterns: [ExfiltrationPattern] = []

        // Group downloads by time windows (30 min)
        let downloads = events.filter { $0.eventType == .downloaded || $0.eventType == .shared }
        guard !downloads.isEmpty else { return [] }

        var processed = Set<UUID>()
        for event in downloads {
            guard !processed.contains(event.id) else { continue }

            let window = downloads.filter {
                abs($0.timestamp.timeIntervalSince(event.timestamp)) < 1800
            }
            if window.count >= 5 {
                let totalSize = window.compactMap { $0.fileSize }.reduce(0, +)
                let ips = Set(window.compactMap { $0.ipAddress }).filter { isExternalIP($0) }

                let pattern = ExfiltrationPattern(
                    suspectedFiles: window,
                    totalSize: totalSize,
                    timeWindow: 1800,
                    destinationIPs: Array(ips),
                    riskScore: min(100, window.count * 4 + (ips.isEmpty ? 0 : 30)),
                    description: "\(window.count) files (\(ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file))) transferred in 30 min"
                )
                patterns.append(pattern)
                window.forEach { processed.insert($0.id) }
            }
        }

        return patterns.sorted { $0.riskScore > $1.riskScore }
    }

    // MARK: - Helpers

    private func extractTimestamp(from line: String) -> Date? {
        // Try ISO 8601 patterns
        let isoPatterns = [
            #"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?Z?"#,
            #"\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}"#,
            #"\d{2}/\d{2}/\d{4} \d{2}:\d{2}:\d{2}"#
        ]
        for pattern in isoPatterns {
            if let range = line.range(of: pattern, options: .regularExpression) {
                let match = String(line[range])
                if let date = parseFlexibleDate(match) { return date }
            }
        }
        return nil
    }

    private func parseISO8601(_ string: String) -> Date? {
        let formats = [
            ISO8601DateFormatter(),
        ]
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: string) { return d }
        let f2 = ISO8601DateFormatter()
        f2.formatOptions = [.withInternetDateTime]
        return f2.date(from: string)
    }

    private func parseFlexibleDate(_ string: String) -> Date? {
        if let d = parseISO8601(string) { return d }
        let formats = [
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd HH:mm:ss Z",
            "MM/dd/yyyy HH:mm:ss",
            "dd/MM/yyyy HH:mm:ss",
            "yyyy-MM-dd HH:mm:ss.SSS"
        ]
        let f = DateFormatter()
        for format in formats {            f.dateFormat = format
            if let d = f.date(from: string.trimmingCharacters(in: .whitespaces)) { return d }
        }
        return nil
    }

    private func extractValue(from line: String, key: String) -> String? {
        // Try key=value, key:value, "key":"value"
        let patterns = [
            "\(key)=([^\\s,;|]+)",
            "\(key):\\s*([^\\s,;|]+)",
            #""\#(key)"\s*:\s*"([^"]+)""#,
            "\(key)=\\\"([^\\\"]+)\\\""
        ]
        for pattern in patterns {
            if let range = line.range(of: pattern, options: [.regularExpression, .caseInsensitive]),
               let capture = extractFirstCapture(from: String(line[range]), pattern: pattern) {
                return capture
            }
        }
        return nil
    }

    private func extractFirstCapture(from string: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: string, range: NSRange(string.startIndex..., in: string)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: string) else { return nil }
        return String(string[range])
    }

    private func extractIPAddress(from line: String) -> String? {
        let pattern = #"\b(?:\d{1,3}\.){3}\d{1,3}\b"#
        if let range = line.range(of: pattern, options: .regularExpression) {
            return String(line[range])
        }
        return nil
    }

    private func extractFilenameFromLine(_ line: String) -> String? {
        // Look for path-like strings
        let pattern = #"[/\\][\w\-. /\\]+"#
        if let range = line.range(of: pattern, options: .regularExpression) {
            return URL(fileURLWithPath: String(line[range])).lastPathComponent
        }
        return nil
    }
}

// MARK: - Demo Log Generator (for testing)
extension LogParser {
    static func generateDemoLogs(provider: CloudProvider, count: Int = 50) -> String {
        var lines: [String] = []
        let calendar = Calendar.current
        let now = Date()
        let isoFormatter = ISO8601DateFormatter()

        let files = [
            "/Documents/Q4_Financial_Report.pdf",
            "/Documents/Employee_Database.xlsx",
            "/Projects/source_code.zip",
            "/Personal/passwords_backup.txt",
            "/HR/salary_data.xlsx",
            "/Legal/contracts_2024.pdf",
            "/IT/server_credentials.txt",
            "/Marketing/client_list.csv",
            "/Finance/audit_report.pdf",
            "/Engineering/api_keys.json"
        ]

        let operations: [(FileEventType, Int)] = [
            (.uploaded, 20), (.downloaded, 25), (.deleted, 10),
            (.modified, 15), (.shared, 8), (.accessed, 22)
        ]

        let users = ["alice@company.com", "bob@company.com", "charlie@company.com", "unknown_user@external.com"]
        let devices = ["MacBook-Pro-Alice", "iPhone-14-Bob", "Windows-PC-Charlie", "Unknown-Device"]
        let ips = ["192.168.1.100", "192.168.1.101", "203.0.113.42", "198.51.100.7"]

        for _ in 0..<count {
            let daysBack = Int.random(in: 0...30)
            let hoursBack = Int.random(in: 0...23)
            guard let date = calendar.date(byAdding: .hour, value: -(daysBack * 24 + hoursBack), to: now) else { continue }

            let f = ISO8601DateFormatter()
            let timestamp = f.string(from: date)
            let file = files.randomElement()!
            let fileName = URL(fileURLWithPath: file).lastPathComponent
            let (opType, _) = operations.randomElement()!
            let user = users.randomElement()!
            let device = devices.randomElement()!
            let ip = ips.randomElement()!
            let size = Int64.random(in: 10_000...50_000_000)

            switch provider {
            case .iCloud:
                lines.append("\(timestamp) [INFO] CloudDocs: file_op=\(opType.rawValue.uppercased()) path=\(file) size=\(size) device=\(device) user=\(user) ip=\(ip)")
            case .googleDrive:
                let json = """
                {"time":"\(timestamp)","actor":{"email":"\(user)"},"events":[{"type":"access","name":"\(opType.rawValue.lowercased())","parameters":[{"name":"doc_title","value":"\(fileName)"},{"name":"file_size","value":"\(size)"}]}],"ipAddress":"\(ip)"}
                """
                lines.append(json)
            case .dropbox:
                lines.append("\(timestamp) | \(user) | file_ops.\(opType.rawValue.lowercased()) | \(file) | \(size) bytes | \(ip) | \(device)")
            case .oneDrive:
                lines.append("\(timestamp),UserPrincipalName,\(user),Operation,File\(opType.rawValue),FileName,\(fileName),FilePath,\(file),FileSize,\(size),ClientIP,\(ip),DeviceName,\(device)")
            default:
                lines.append("\(timestamp) \(opType.rawValue.uppercased()) path=\(file) size=\(size) user=\(user) ip=\(ip)")
            }
        }

        // Add anomalous burst (mass deletion)
        let burstTime = isoFormatter.string(from: calendar.date(byAdding: .hour, value: -2, to: now) ?? now)
        for j in 0..<12 {
            let sensitiveFile = files[j % files.count]
            lines.append("\(burstTime) [WARN] CloudDocs: file_op=DELETE path=\(sensitiveFile) size=1024000 device=Unknown-Device user=unknown_user@external.com ip=203.0.113.42")
        }

        return lines.shuffled().joined(separator: "\n")
    }
}
