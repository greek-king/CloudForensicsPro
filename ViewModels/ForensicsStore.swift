// ViewModels/ForensicsStore.swift
import Foundation
import SwiftUI
import UniformTypeIdentifiers

class ForensicsStore: ObservableObject {

    // MARK: - Published State
    @Published var cases: [ForensicsCase] = []
    @Published var activeCase: ForensicsCase? = nil
    @Published var isAnalyzing: Bool = false
    @Published var analysisProgress: Double = 0.0
    @Published var analysisStep: String = ""
    @Published var errorMessage: String? = nil
    @Published var selectedProvider: CloudProvider = .iCloud
    @Published var filterEventType: FileEventType? = nil
    @Published var filterAnomalyOnly: Bool = false
    @Published var searchQuery: String = ""
    @Published var sortOrder: SortOrder = .dateDesc

    enum SortOrder: String, CaseIterable {
        case dateDesc  = "Newest first"
        case dateAsc   = "Oldest first"
        case severity  = "By severity"
        case filename  = "By filename"
    }

    private let parser = LogParser()
    private let casesKey = "forensics_cases_v1"

    init() { loadCases() }

    // MARK: - Computed

    var filteredEvents: [FileEvent] {
        guard let c = activeCase else { return [] }
        var events = c.events

        if let type = filterEventType {
            events = events.filter { $0.eventType == type }
        }
        if filterAnomalyOnly {
            events = events.filter { $0.isAnomaly }
        }
        if !searchQuery.isEmpty {
            events = events.filter {
                $0.fileName.localizedCaseInsensitiveContains(searchQuery) ||
                $0.filePath.localizedCaseInsensitiveContains(searchQuery) ||
                ($0.userID ?? "").localizedCaseInsensitiveContains(searchQuery) ||
                ($0.ipAddress ?? "").contains(searchQuery)
            }
        }
        switch sortOrder {
        case .dateDesc:  events.sort { $0.timestamp > $1.timestamp }
        case .dateAsc:   events.sort { $0.timestamp < $1.timestamp }
        case .severity:  events.sort { $0.eventType.severity > $1.eventType.severity }
        case .filename:  events.sort { $0.fileName < $1.fileName }
        }
        return events
    }

    var timelineEntries: [TimelineEntry] {
        guard let c = activeCase else { return [] }
        let calendar = Calendar.current
        var grouped: [Date: [FileEvent]] = [:]
        for event in c.events {
            let day = calendar.startOfDay(for: event.timestamp)
            grouped[day, default: []].append(event)
        }
        return grouped.map { TimelineEntry(id: UUID(), date: $0.key, events: $0.value) }
            .sorted { $0.date > $1.date }
    }

    var exfiltrationPatterns: [ExfiltrationPattern] {
        guard let c = activeCase else { return [] }
        return parser.detectExfiltration(in: c.events)
    }

    // MARK: - Analysis

    func analyzeText(_ text: String, provider: CloudProvider, caseName: String) {
        isAnalyzing = true
        analysisProgress = 0
        errorMessage = nil

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            self.updateProgress(0.1, step: "Reading log data...")
            Thread.sleep(forTimeInterval: 0.3)

            self.updateProgress(0.3, step: "Parsing \(provider.rawValue) format...")
            let result = self.parser.parse(text: text, provider: provider)
            Thread.sleep(forTimeInterval: 0.3)

            self.updateProgress(0.6, step: "Running anomaly detection...")
            Thread.sleep(forTimeInterval: 0.4)

            self.updateProgress(0.8, step: "Generating findings...")
            let findings = self.generateFindings(from: result.events)
            Thread.sleep(forTimeInterval: 0.3)

            self.updateProgress(0.95, step: "Building timeline...")

            let newCase = ForensicsCase(
                id: UUID(),
                name: caseName.isEmpty ? "\(provider.rawValue) Analysis \(Date().formatted(date: .abbreviated, time: .omitted))" : caseName,
                description: "\(result.eventsFound) events parsed from \(result.linesProcessed) log lines",
                createdAt: Date(),
                providers: [provider],
                events: result.events,
                findings: findings,
                status: .active,
                tags: []
            )

            DispatchQueue.main.async {
                self.cases.insert(newCase, at: 0)
                self.activeCase = newCase
                self.isAnalyzing = false
                self.analysisProgress = 1.0
                self.saveData()
            }
        }
    }

    func loadDemoCase(provider: CloudProvider) {
        let demoLog = LogParser.generateDemoLogs(provider: provider, count: 60)
        analyzeText(demoLog, provider: provider, caseName: "Demo — \(provider.rawValue)")
    }

    private func updateProgress(_ value: Double, step: String) {
        DispatchQueue.main.async { [weak self] in
            self?.analysisProgress = value
            self?.analysisStep = step
        }
    }

    // MARK: - Findings Generator

    private func generateFindings(from events: [FileEvent]) -> [Finding] {
        var findings: [Finding] = []

        // Mass deletion finding
        let deletions = events.filter { $0.eventType == .deleted }
        if deletions.count > 10 {
            findings.append(Finding(
                id: UUID(),
                title: "Mass file deletion detected",
                description: "\(deletions.count) files were deleted. This could indicate data destruction, ransomware activity, or an insider threat covering tracks.",
                severity: .high,
                relatedEventIDs: deletions.prefix(20).map { $0.id },
                timestamp: deletions.first?.timestamp ?? Date(),
                category: .deletion
            ))
        }

        // External sharing
        let shares = events.filter { $0.eventType == .shared }
        if !shares.isEmpty {
            findings.append(Finding(
                id: UUID(),
                title: "\(shares.count) file sharing events",
                description: "Files were shared externally. Review recipients and verify all sharing was authorized.",
                severity: shares.count > 5 ? .high : .medium,
                relatedEventIDs: shares.map { $0.id },
                timestamp: shares.first?.timestamp ?? Date(),
                category: .sharing
            ))
        }

        // Off-hours activity
        let calendar = Calendar.current
        let offHours = events.filter {
            let h = calendar.component(.hour, from: $0.timestamp)
            return h >= 22 || h < 6
        }
        if offHours.count > 5 {
            findings.append(Finding(
                id: UUID(),
                title: "Significant off-hours activity",
                description: "\(offHours.count) file operations occurred outside business hours (10pm–6am). Review for unauthorized access.",
                severity: .medium,
                relatedEventIDs: offHours.map { $0.id },
                timestamp: offHours.first?.timestamp ?? Date(),
                category: .timing
            ))
        }

        // Sensitive file access
        let sensitiveAccess = events.filter { $0.isSensitiveFile && ($0.eventType == .downloaded || $0.eventType == .deleted) }
        if !sensitiveAccess.isEmpty {
            findings.append(Finding(
                id: UUID(),
                title: "Sensitive files accessed",
                description: "\(sensitiveAccess.count) sensitive files (PDF, XLS, credentials, archives) were downloaded or deleted.",
                severity: .high,
                relatedEventIDs: sensitiveAccess.map { $0.id },
                timestamp: sensitiveAccess.first?.timestamp ?? Date(),
                category: .exfiltration
            ))
        }

        // Unknown devices
        let knownDevices = Set(events.compactMap { $0.deviceName }.filter { !$0.contains("Unknown") })
        let unknownDeviceEvents = events.filter {
            if let d = $0.deviceName { return d.contains("Unknown") || d.contains("unknown") }
            return $0.deviceName == nil && $0.ipAddress != nil
        }
        if !unknownDeviceEvents.isEmpty {
            findings.append(Finding(
                id: UUID(),
                title: "Activity from unknown devices",
                description: "\(unknownDeviceEvents.count) events from unrecognized devices. Known devices: \(knownDevices.joined(separator: ", "))",
                severity: .medium,
                relatedEventIDs: unknownDeviceEvents.map { $0.id },
                timestamp: unknownDeviceEvents.first?.timestamp ?? Date(),
                category: .device
            ))
        }

        // Anomalies summary
        let anomalies = events.filter { $0.isAnomaly }
        if anomalies.count > 0 {
            findings.append(Finding(
                id: UUID(),
                title: "\(anomalies.count) anomalous events flagged",
                description: "Automated analysis flagged \(anomalies.count) events as potentially suspicious. Manual review recommended.",
                severity: anomalies.count > 20 ? .high : .medium,
                relatedEventIDs: anomalies.map { $0.id },
                timestamp: anomalies.first?.timestamp ?? Date(),
                category: .anomaly
            ))
        }

        return findings.sorted { $0.severity > $1.severity }
    }

    // MARK: - Case Management

    func deleteCase(id: UUID) {
        cases.removeAll { $0.id == id }
        if activeCase?.id == id { activeCase = nil }
        saveData()
    }

    func exportReport(for c: ForensicsCase) -> String {
        var report = """
        ╔══════════════════════════════════════════════════════╗
        ║           CLOUD SYNC FORENSICS REPORT               ║
        ╚══════════════════════════════════════════════════════╝

        Case Name:     \(c.name)
        Generated:     \(Date().formatted())
        Providers:     \(c.providers.map { $0.rawValue }.joined(separator: ", "))
        Date Range:    \(c.dateRange)
        Risk Level:    \(c.riskLevel.label) (\(c.riskScore)/100)

        ══════════════════════════════════════════════════════
        SUMMARY
        ══════════════════════════════════════════════════════
        Total Events:  \(c.totalEvents)
        Anomalies:     \(c.anomalyCount)
        Deletions:     \(c.deletedCount)
        Shares:        \(c.sharedCount)

        ══════════════════════════════════════════════════════
        FINDINGS (\(c.findings.count))
        ══════════════════════════════════════════════════════

        """

        for (i, finding) in c.findings.enumerated() {
            report += """
            [\(i+1)] [\(finding.severity.label.uppercased())] \(finding.title)
                Category: \(finding.category.rawValue)
                \(finding.description)
                Related events: \(finding.relatedEventIDs.count)

            """
        }

        report += """

        ══════════════════════════════════════════════════════
        ANOMALOUS EVENTS
        ══════════════════════════════════════════════════════

        """

        let anomalies = c.events.filter { $0.isAnomaly }
        for event in anomalies.prefix(50) {
            report += "[\(event.formattedTimestamp)] \(event.eventType.rawValue.uppercased()) \(event.fileName)\n"
            if let reason = event.anomalyReason {
                report += "  ⚠ \(reason)\n"
            }
            if let ip = event.ipAddress { report += "  IP: \(ip)\n" }
            if let user = event.userID { report += "  User: \(user)\n" }
            report += "\n"
        }

        report += """

        ══════════════════════════════════════════════════════
        FULL EVENT LOG (\(c.events.count) events)
        ══════════════════════════════════════════════════════

        """

        for event in c.events.prefix(200) {
            report += "[\(event.formattedTimestamp)] [\(event.eventType.rawValue)] \(event.fileName)"
            if let user = event.userID { report += " | \(user)" }
            if let ip   = event.ipAddress { report += " | \(ip)" }
            if event.isAnomaly { report += " ⚠ ANOMALY" }
            report += "\n"
        }

        report += "\n— End of Report —\n"
        return report
    }

    // MARK: - Persistence

    private func saveData() {
        if let d = try? JSONEncoder().encode(cases) {
            UserDefaults.standard.set(d, forKey: casesKey)
        }
    }

    private func loadCases() {
        if let d = UserDefaults.standard.data(forKey: casesKey),
           let loaded = try? JSONDecoder().decode([ForensicsCase].self, from: d) {
            cases = loaded
            activeCase = cases.first
        }
    }
}
