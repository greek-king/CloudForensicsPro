// Views/ContentView.swift
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: ForensicsStore
    @State private var selectedTab = 0

    var body: some View {
        ZStack {
            Color(hex: "#0A0A0F").ignoresSafeArea()

            if store.isAnalyzing {
                AnalyzingView()
                    .transition(.opacity)
                    .zIndex(10)
            } else {
                TabView(selection: $selectedTab) {
                    CasesView()
                        .tabItem { Label("Cases", systemImage: "folder.fill") }
                        .tag(0)

                    if store.activeCase != nil {
                        TimelineView()
                            .tabItem { Label("Timeline", systemImage: "timeline.selection") }
                            .tag(1)

                        EventsView()
                            .tabItem { Label("Events", systemImage: "list.bullet.rectangle.fill") }
                            .tag(2)

                        FindingsView()
                            .tabItem { Label("Findings", systemImage: "exclamationmark.triangle.fill") }
                            .tag(3)
                    }
                }
                .tint(Color(hex: "#00D4FF"))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: store.isAnalyzing)
    }
}

// MARK: - Analyzing View
struct AnalyzingView: View {
    @EnvironmentObject var store: ForensicsStore
    @State private var rotation: Double = 0

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color(hex: "#0A0A0F").ignoresSafeArea()

                RadialGradient(
                    colors: [Color(hex: "#001A2E").opacity(0.8), Color.clear],
                    center: .center, startRadius: 0, endRadius: geo.size.height * 0.5
                ).ignoresSafeArea()

                VStack(spacing: 32) {
                    Spacer()

                    // Spinning forensics icon
                    ZStack {
                        ForEach(0..<3) { i in
                            Circle()
                                .strokeBorder(Color(hex: "#00D4FF").opacity(0.08 + Double(i) * 0.04), lineWidth: 1)
                                .frame(width: CGFloat(100 + i * 40), height: CGFloat(100 + i * 40))
                        }
                        Circle()
                            .trim(from: 0, to: 0.7)
                            .stroke(Color(hex: "#00D4FF"), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                            .frame(width: 80, height: 80)
                            .rotationEffect(.degrees(rotation))
                            .onAppear {
                                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                                    rotation = 360
                                }
                            }
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 28))
                            .foregroundColor(Color(hex: "#00D4FF"))
                    }

                    VStack(spacing: 12) {
                        Text(store.analysisStep)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white)

                        GeometryReader { bar in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.06)).frame(height: 6)
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(LinearGradient(
                                        colors: [Color(hex: "#0052D4"), Color(hex: "#00D4FF")],
                                        startPoint: .leading, endPoint: .trailing
                                    ))
                                    .frame(width: max(6, bar.size.width * store.analysisProgress), height: 6)
                                    .animation(.easeInOut(duration: 0.3), value: store.analysisProgress)
                            }
                        }
                        .frame(height: 6)
                        .padding(.horizontal, 40)

                        Text("\(Int(store.analysisProgress * 100))%")
                            .font(.system(size: 13))
                            .foregroundColor(Color(hex: "#00D4FF").opacity(0.6))
                    }

                    Spacer()
                }
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Cases View
struct CasesView: View {
    @EnvironmentObject var store: ForensicsStore
    @State private var showImport = false
    @State private var showNewCase = false

    var body: some View {
        NavigationView {
            ZStack {
                Color(hex: "#0A0A0F").ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        // Header
                        VStack(spacing: 6) {
                            HStack(spacing: 10) {
                                Image(systemName: "shield.lefthalf.filled")
                                    .font(.system(size: 28))
                                    .foregroundStyle(LinearGradient(
                                        colors: [Color(hex: "#0052D4"), Color(hex: "#00D4FF")],
                                        startPoint: .top, endPoint: .bottom
                                    ))
                                Text("Cloud Forensics")
                                    .font(.system(size: 26, weight: .black, design: .rounded))
                                    .foregroundStyle(LinearGradient(
                                        colors: [Color(hex: "#00D4FF"), Color(hex: "#0052D4")],
                                        startPoint: .leading, endPoint: .trailing
                                    ))
                            }
                            Text("Cloud sync log analysis & investigation")
                                .font(.system(size: 13))
                                .foregroundColor(Color(hex: "#00D4FF").opacity(0.5))
                        }
                        .padding(.top, 24)
                        .padding(.bottom, 24)

                        if store.cases.isEmpty {
                            // Empty state
                            VStack(spacing: 20) {
                                Image(systemName: "cloud.fill")
                                    .font(.system(size: 60))
                                    .foregroundColor(Color(hex: "#00D4FF").opacity(0.15))
                                    .padding(.top, 40)

                                Text("No investigations yet")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(Color.white.opacity(0.4))

                                Text("Import cloud logs or load demo data\nto start analyzing")
                                    .font(.system(size: 14))
                                    .foregroundColor(Color.white.opacity(0.25))
                                    .multilineTextAlignment(.center)

                                // Quick start buttons
                                VStack(spacing: 10) {
                                    ForEach([CloudProvider.iCloud, .googleDrive, .dropbox, .oneDrive], id: \.self) { provider in
                                        Button(action: { store.loadDemoCase(provider: provider) }) {
                                            HStack(spacing: 12) {
                                                Image(systemName: provider.icon)
                                                    .font(.system(size: 18))
                                                    .foregroundColor(provider.color)
                                                    .frame(width: 32)
                                                Text("Demo: \(provider.rawValue)")
                                                    .font(.system(size: 14, weight: .semibold))
                                                    .foregroundColor(.white)
                                                Spacer()
                                                Image(systemName: "play.fill")
                                                    .font(.system(size: 12))
                                                    .foregroundColor(Color(hex: "#00D4FF").opacity(0.5))
                                            }
                                            .padding(.horizontal, 16).padding(.vertical, 14)
                                            .background(
                                                RoundedRectangle(cornerRadius: 14)
                                                    .fill(provider.color.opacity(0.06))
                                                    .overlay(RoundedRectangle(cornerRadius: 14)
                                                        .strokeBorder(provider.color.opacity(0.15), lineWidth: 0.5))
                                            )
                                        }
                                    }
                                }
                                .padding(.horizontal, 24)
                                .padding(.top, 8)
                            }
                        } else {
                            // Cases list
                            VStack(spacing: 10) {
                                ForEach(store.cases) { c in
                                    CaseCard(forensicsCase: c)
                                        .onTapGesture { store.activeCase = c }
                                        .contextMenu {
                                            Button(role: .destructive) {
                                                store.deleteCase(id: c.id)
                                            } label: { Label("Delete", systemImage: "trash") }
                                        }
                                }
                            }
                            .padding(.horizontal, 20)

                            // Load demo
                            VStack(spacing: 8) {
                                Text("LOAD DEMO DATA")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(Color(hex: "#00D4FF").opacity(0.4))
                                    .tracking(1.5)
                                    .padding(.top, 24)

                                HStack(spacing: 8) {
                                    ForEach([CloudProvider.iCloud, .googleDrive, .dropbox, .oneDrive], id: \.self) { p in
                                        Button(action: { store.loadDemoCase(provider: p) }) {
                                            VStack(spacing: 4) {
                                                Image(systemName: p.icon).font(.system(size: 16)).foregroundColor(p.color)
                                                Text(p.rawValue.components(separatedBy: " ").first ?? p.rawValue)
                                                    .font(.system(size: 9, weight: .bold))
                                                    .foregroundColor(Color.white.opacity(0.4))
                                            }
                                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                                            .background(RoundedRectangle(cornerRadius: 10)
                                                .fill(p.color.opacity(0.06))
                                                .overlay(RoundedRectangle(cornerRadius: 10)
                                                    .strokeBorder(p.color.opacity(0.15), lineWidth: 0.5)))
                                        }
                                    }
                                }
                                .padding(.horizontal, 20)
                            }
                        }

                        Spacer().frame(height: 40)
                    }
                }

                // FAB
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button(action: { showNewCase = true }) {
                            Image(systemName: "plus")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.black)
                                .frame(width: 56, height: 56)
                                .background(Circle().fill(LinearGradient(
                                    colors: [Color(hex: "#00D4FF"), Color(hex: "#0052D4")],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                )))
                                .shadow(color: Color(hex: "#00D4FF").opacity(0.4), radius: 12)
                        }
                        .padding(.trailing, 24).padding(.bottom, 24)
                    }
                }
            }
            .navigationBarHidden(true)
        }
        .sheet(isPresented: $showNewCase) { NewCaseSheet() }
    }
}

// MARK: - Case Card
struct CaseCard: View {
    @EnvironmentObject var store: ForensicsStore
    let forensicsCase: ForensicsCase
    var isActive: Bool { store.activeCase?.id == forensicsCase.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                // Provider icons
                HStack(spacing: 4) {
                    ForEach(forensicsCase.providers, id: \.self) { p in
                        Image(systemName: p.icon).font(.system(size: 14)).foregroundColor(p.color)
                    }
                }
                Spacer()
                // Risk badge
                Text(forensicsCase.riskLevel.label.uppercased())
                    .font(.system(size: 9, weight: .black))
                    .foregroundColor(forensicsCase.riskLevel.color)
                    .tracking(1)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().fill(forensicsCase.riskLevel.color.opacity(0.12))
                        .overlay(Capsule().strokeBorder(forensicsCase.riskLevel.color.opacity(0.3), lineWidth: 0.5)))
            }

            Text(forensicsCase.name)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.white)

            HStack(spacing: 16) {
                Label("\(forensicsCase.totalEvents) events", systemImage: "list.bullet")
                Label("\(forensicsCase.anomalyCount) anomalies", systemImage: "exclamationmark.triangle")
                    .foregroundColor(forensicsCase.anomalyCount > 0 ? Color(hex: "#FF9500") : Color.white.opacity(0.3))
            }
            .font(.system(size: 12))
            .foregroundColor(Color.white.opacity(0.4))

            Text(forensicsCase.dateRange)
                .font(.system(size: 11))
                .foregroundColor(Color.white.opacity(0.25))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(isActive ? 0.06 : 0.03))
                .overlay(RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        isActive ? Color(hex: "#00D4FF").opacity(0.4) : Color.white.opacity(0.06),
                        lineWidth: isActive ? 1 : 0.5
                    ))
        )
    }
}

// MARK: - Timeline View
struct TimelineView: View {
    @EnvironmentObject var store: ForensicsStore

    var body: some View {
        NavigationView {
            ZStack {
                Color(hex: "#0A0A0F").ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {

                        if let c = store.activeCase {
                            // Risk overview
                            RiskOverviewCard(forensicsCase: c)
                                .padding(.horizontal, 20).padding(.top, 16)

                            // Stats row
                            HStack(spacing: 10) {
                                ForensicsStat(label: "Events",    value: "\(c.totalEvents)",    color: "#00D4FF")
                                ForensicsStat(label: "Anomalies", value: "\(c.anomalyCount)",   color: "#FF9500")
                                ForensicsStat(label: "Deleted",   value: "\(c.deletedCount)",   color: "#FF3B30")
                                ForensicsStat(label: "Shared",    value: "\(c.sharedCount)",    color: "#FF2D55")
                            }
                            .padding(.horizontal, 20).padding(.top, 12)

                            // Findings bar
                            if !c.findings.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("TOP FINDINGS")
                                        .font(.system(size: 10, weight: .black))
                                        .foregroundColor(Color(hex: "#00D4FF").opacity(0.5))
                                        .tracking(1.5)
                                    ForEach(c.findings.prefix(3)) { finding in
                                        FindingRow(finding: finding)
                                    }
                                }
                                .padding(.horizontal, 20).padding(.top, 20)
                            }

                            // Timeline
                            VStack(alignment: .leading, spacing: 0) {
                                Text("ACTIVITY TIMELINE")
                                    .font(.system(size: 10, weight: .black))
                                    .foregroundColor(Color(hex: "#00D4FF").opacity(0.5))
                                    .tracking(1.5)
                                    .padding(.horizontal, 20).padding(.top, 24).padding(.bottom, 12)

                                ForEach(store.timelineEntries) { entry in
                                    TimelineEntryRow(entry: entry)
                                }
                            }
                        }

                        Spacer().frame(height: 40)
                    }
                }
            }
            .navigationTitle("Timeline")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark)
        }
    }
}

struct TimelineEntryRow: View {
    let entry: TimelineEntry

    var body: some View {
        HStack(spacing: 0) {
            // Date column
            VStack(spacing: 2) {
                Text(entry.date.formatted(.dateTime.day()))
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundColor(entry.isAnomaly ? Color(hex: "#FF9500") : .white)
                Text(entry.date.formatted(.dateTime.month(.abbreviated)))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Color.white.opacity(0.4))
            }
            .frame(width: 50)

            // Timeline line
            VStack(spacing: 0) {
                Circle()
                    .fill(entry.isAnomaly ? Color(hex: "#FF9500") : Color(hex: "#00D4FF"))
                    .frame(width: 8, height: 8)
                    .shadow(color: entry.isAnomaly ? Color(hex: "#FF9500").opacity(0.5) : Color(hex: "#00D4FF").opacity(0.5), radius: 4)
                Rectangle()
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 1)
                    .frame(maxHeight: .infinity)
            }
            .frame(width: 32)

            // Events summary
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text("\(entry.events.count) events")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                    if entry.isAnomaly {
                        Text("ANOMALY")
                            .font(.system(size: 9, weight: .black))
                            .foregroundColor(Color(hex: "#FF9500"))
                            .tracking(1)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(Color(hex: "#FF9500").opacity(0.12)))
                    }
                }
                // Event type breakdown
                let grouped = Dictionary(grouping: entry.events) { $0.eventType }
                HStack(spacing: 8) {
                    ForEach(grouped.sorted(by: { $0.value.count > $1.value.count }).prefix(4), id: \.key.rawValue) { type, events in
                        HStack(spacing: 3) {
                            Circle().fill(type.color).frame(width: 5, height: 5)
                            Text("\(events.count)")
                                .font(.system(size: 11))
                                .foregroundColor(Color.white.opacity(0.4))
                        }
                    }
                }
            }
            .padding(.leading, 8)
            .padding(.vertical, 14)

            Spacer()
        }
        .padding(.horizontal, 20)
    }
}

// MARK: - Events View
struct EventsView: View {
    @EnvironmentObject var store: ForensicsStore

    var body: some View {
        NavigationView {
            ZStack {
                Color(hex: "#0A0A0F").ignoresSafeArea()

                VStack(spacing: 0) {
                    // Filter bar
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            FilterPill(label: "All", isSelected: store.filterEventType == nil) {
                                store.filterEventType = nil
                            }
                            FilterPill(label: "Anomalies only",
                                       isSelected: store.filterAnomalyOnly,
                                       color: "#FF9500") {
                                store.filterAnomalyOnly.toggle()
                            }
                            ForEach(FileEventType.allCases.prefix(6), id: \.rawValue) { type in
                                FilterPill(label: type.rawValue,
                                           isSelected: store.filterEventType == type,
                                           color: type.color.description) {
                                    store.filterEventType = store.filterEventType == type ? nil : type
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    .padding(.vertical, 10)
                    .background(Color(hex: "#0A0A0F"))

                    // Search
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass").font(.system(size: 13))
                            .foregroundColor(Color(hex: "#00D4FF").opacity(0.5))
                        TextField("Search files, users, IPs...", text: $store.searchQuery)
                            .font(.system(size: 14)).foregroundColor(.white)
                            .tint(Color(hex: "#00D4FF"))
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.04))
                        .overlay(RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color(hex: "#00D4FF").opacity(0.1), lineWidth: 0.5)))
                    .padding(.horizontal, 20).padding(.bottom, 10)

                    // Events list
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 6) {
                            ForEach(store.filteredEvents) { event in
                                EventRow(event: event)
                                    .padding(.horizontal, 20)
                            }
                            Spacer().frame(height: 30)
                        }
                        .padding(.top, 4)
                    }
                }
            }
            .navigationTitle("Events (\(store.filteredEvents.count))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark)
        }
    }
}

struct EventRow: View {
    let event: FileEvent
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: { withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() } }) {
                HStack(spacing: 12) {
                    // Event type icon
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(event.eventType.color.opacity(0.12))
                            .frame(width: 34, height: 34)
                        Image(systemName: event.eventType.icon)
                            .font(.system(size: 14))
                            .foregroundColor(event.eventType.color)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(event.fileName)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            if event.isAnomaly {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(Color(hex: "#FF9500"))
                            }
                        }
                        HStack(spacing: 8) {
                            Text(event.relativeTimestamp)
                                .font(.system(size: 11))
                                .foregroundColor(Color.white.opacity(0.3))
                            if let user = event.userID {
                                Text("•").foregroundColor(Color.white.opacity(0.15))
                                Text(user.components(separatedBy: "@").first ?? user)
                                    .font(.system(size: 11))
                                    .foregroundColor(Color(hex: "#00D4FF").opacity(0.5))
                            }
                        }
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 3) {
                        if event.fileSize != nil {
                            Text(event.formattedSize)                                .font(.system(size: 11))
                                .foregroundColor(Color.white.opacity(0.3))
                        }
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10))
                            .foregroundColor(Color.white.opacity(0.2))
                    }
                }
                .padding(12)
            }
            .buttonStyle(PlainButtonStyle())

            if expanded {
                VStack(alignment: .leading, spacing: 8) {
                    Divider().overlay(Color.white.opacity(0.06))

                    Group {
                        DetailRow(label: "Path", value: event.filePath)
                        DetailRow(label: "Time", value: event.formattedTimestamp)
                        if let ip = event.ipAddress { DetailRow(label: "IP Address", value: ip) }
                        if let device = event.deviceName { DetailRow(label: "Device", value: device) }
                        if let checksum = event.checksum { DetailRow(label: "Hash", value: checksum) }
                        if let prev = event.previousPath { DetailRow(label: "Previous path", value: prev) }
                        if let reason = event.anomalyReason {
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(Color(hex: "#FF9500"))
                                Text(reason)
                                    .font(.system(size: 12))
                                    .foregroundColor(Color(hex: "#FF9500").opacity(0.8))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.top, 2)
                        }
                    }
                    .padding(.horizontal, 12)
                }
                .padding(.bottom, 12)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(event.isAnomaly ? Color(hex: "#FF9500").opacity(0.04) : Color.white.opacity(0.03))
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        event.isAnomaly ? Color(hex: "#FF9500").opacity(0.2) : Color.white.opacity(0.05),
                        lineWidth: 0.5
                    ))
        )
    }
}

struct DetailRow: View {
    let label: String
    let value: String
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label + ":")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color.white.opacity(0.3))
                .frame(width: 80, alignment: .trailing)
            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(Color.white.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Findings View
struct FindingsView: View {
    @EnvironmentObject var store: ForensicsStore

    var body: some View {
        NavigationView {
            ZStack {
                Color(hex: "#0A0A0F").ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {
                        if let c = store.activeCase {
                            // Exfiltration patterns
                            if !store.exfiltrationPatterns.isEmpty {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("EXFILTRATION PATTERNS")
                                        .font(.system(size: 10, weight: .black))
                                        .foregroundColor(Color(hex: "#FF3B30").opacity(0.7))
                                        .tracking(1.5)

                                    ForEach(store.exfiltrationPatterns.indices, id: \.self) { i in
                                        ExfiltrationCard(pattern: store.exfiltrationPatterns[i])
                                    }
                                }
                                .padding(.horizontal, 20).padding(.top, 16)
                            }

                            // Findings
                            VStack(alignment: .leading, spacing: 10) {
                                Text("FINDINGS (\(c.findings.count))")
                                    .font(.system(size: 10, weight: .black))
                                    .foregroundColor(Color(hex: "#00D4FF").opacity(0.5))
                                    .tracking(1.5)

                                ForEach(c.findings) { finding in
                                    FindingCard(finding: finding)
                                }
                            }
                            .padding(.horizontal, 20).padding(.top, 16)

                            // Export button
                            Button(action: exportReport) {
                                HStack(spacing: 10) {
                                    Image(systemName: "square.and.arrow.up")
                                    Text("Export Full Report")
                                        .font(.system(size: 15, weight: .bold))
                                }
                                .foregroundColor(Color(hex: "#00D4FF"))
                                .frame(maxWidth: .infinity).padding(.vertical, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(Color(hex: "#00D4FF").opacity(0.06))
                                        .overlay(RoundedRectangle(cornerRadius: 14)
                                            .strokeBorder(Color(hex: "#00D4FF").opacity(0.2), lineWidth: 0.5))
                                )
                            }
                            .padding(.horizontal, 20).padding(.top, 16)
                        }

                        Spacer().frame(height: 40)
                    }
                }
            }
            .navigationTitle("Findings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark)
        }
    }

    private func exportReport() {
        guard let c = store.activeCase else { return }
        let report = store.exportReport(for: c)
        let av = UIActivityViewController(activityItems: [report], applicationActivities: nil)
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.rootViewController?
            .present(av, animated: true)
    }
}

struct FindingCard: View {
    let finding: Finding

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.system(size: 16))
                    .foregroundColor(finding.severity.color)
                Text(finding.title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
                Text(finding.severity.label.uppercased())
                    .font(.system(size: 9, weight: .black))
                    .foregroundColor(finding.severity.color)
                    .tracking(1)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Capsule().fill(finding.severity.color.opacity(0.12)))
            }
            Text(finding.description)
                .font(.system(size: 13))
                .foregroundColor(Color.white.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Text(finding.category.rawValue)
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "#00D4FF").opacity(0.5))
                Spacer()
                Text("\(finding.relatedEventIDs.count) related events")
                    .font(.system(size: 11))
                    .foregroundColor(Color.white.opacity(0.25))
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(finding.severity.color.opacity(0.04))
                .overlay(RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(finding.severity.color.opacity(0.15), lineWidth: 0.5))
        )
    }
}

struct ExfiltrationCard: View {
    let pattern: ExfiltrationPattern

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "arrow.up.right.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(Color(hex: "#FF3B30"))
                Text("Potential Data Exfiltration")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
                Text("RISK \(pattern.riskScore)")
                    .font(.system(size: 10, weight: .black))
                    .foregroundColor(Color(hex: "#FF3B30"))
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Capsule().fill(Color(hex: "#FF3B30").opacity(0.12)))
            }
            Text(pattern.description)
                .font(.system(size: 13))
                .foregroundColor(Color.white.opacity(0.5))
            if !pattern.destinationIPs.isEmpty {
                Text("External IPs: " + pattern.destinationIPs.joined(separator: ", "))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(Color(hex: "#FF3B30").opacity(0.6))
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(hex: "#FF3B30").opacity(0.04))
                .overlay(RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color(hex: "#FF3B30").opacity(0.2), lineWidth: 0.5))
        )
    }
}

// MARK: - New Case Sheet
struct NewCaseSheet: View {
    @EnvironmentObject var store: ForensicsStore
    @Environment(\.dismiss) var dismiss
    @State private var caseName = ""
    @State private var selectedProvider: CloudProvider = .iCloud
    @State private var logText = ""
    @State private var showingTextEditor = false

    var body: some View {
        NavigationView {
            ZStack {
                Color(hex: "#0A0A0F").ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        // Case name
                        VStack(alignment: .leading, spacing: 8) {
                            Text("CASE NAME").font(.system(size: 10, weight: .black))
                                .foregroundColor(Color(hex: "#00D4FF").opacity(0.5)).tracking(1.5)
                            TextField("e.g. Insider threat investigation Q1", text: $caseName)
                                .font(.system(size: 15)).foregroundColor(.white).tint(Color(hex: "#00D4FF"))
                                .padding(14)
                                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.04))
                                    .overlay(RoundedRectangle(cornerRadius: 12)
                                        .strokeBorder(Color(hex: "#00D4FF").opacity(0.15), lineWidth: 0.5)))
                        }

                        // Provider
                        VStack(alignment: .leading, spacing: 8) {
                            Text("CLOUD PROVIDER").font(.system(size: 10, weight: .black))
                                .foregroundColor(Color(hex: "#00D4FF").opacity(0.5)).tracking(1.5)
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2), spacing: 10) {
                                ForEach(CloudProvider.allCases.filter { $0 != .unknown }, id: \.self) { p in
                                    Button(action: { selectedProvider = p }) {
                                        HStack(spacing: 10) {
                                            Image(systemName: p.icon).font(.system(size: 18)).foregroundColor(p.color)
                                            Text(p.rawValue).font(.system(size: 13, weight: .semibold)).foregroundColor(.white)
                                            Spacer()
                                            if selectedProvider == p {
                                                Image(systemName: "checkmark.circle.fill").font(.system(size: 14)).foregroundColor(p.color)
                                            }
                                        }
                                        .padding(12)
                                        .background(RoundedRectangle(cornerRadius: 12)
                                            .fill(selectedProvider == p ? p.color.opacity(0.1) : Color.white.opacity(0.03))
                                            .overlay(RoundedRectangle(cornerRadius: 12)
                                                .strokeBorder(selectedProvider == p ? p.color.opacity(0.4) : Color.white.opacity(0.06), lineWidth: 0.5)))
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                        }

                        // Log input
                        VStack(alignment: .leading, spacing: 8) {
                            Text("PASTE LOG DATA").font(.system(size: 10, weight: .black))
                                .foregroundColor(Color(hex: "#00D4FF").opacity(0.5)).tracking(1.5)
                            TextEditor(text: $logText)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(Color.white.opacity(0.7))
                                .scrollContentBackground(.hidden)
                                .frame(height: 160)
                                .padding(12)
                                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.04))
                                    .overlay(RoundedRectangle(cornerRadius: 12)
                                        .strokeBorder(Color(hex: "#00D4FF").opacity(0.1), lineWidth: 0.5)))
                            Text("Supports iCloud, Google Drive, Dropbox, OneDrive log formats")
                                .font(.system(size: 11))
                                .foregroundColor(Color.white.opacity(0.25))
                        }

                        // Analyze button
                        Button(action: {
                            let text = logText.isEmpty
                                ? LogParser.generateDemoLogs(provider: selectedProvider)
                                : logText
                            store.analyzeText(text, provider: selectedProvider, caseName: caseName)
                            dismiss()
                        }) {
                            Text(logText.isEmpty ? "Load Demo & Analyze" : "Analyze Logs")
                                .font(.system(size: 16, weight: .black)).tracking(0.5)
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity).padding(.vertical, 16)
                                .background(RoundedRectangle(cornerRadius: 14)
                                    .fill(LinearGradient(
                                        colors: [Color(hex: "#00D4FF"), Color(hex: "#0052D4")],
                                        startPoint: .leading, endPoint: .trailing
                                    )))
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("New Investigation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundColor(Color(hex: "#00D4FF"))
                }
            }
        }
    }
}

// MARK: - Supporting Views
struct RiskOverviewCard: View {
    let forensicsCase: ForensicsCase
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.06), lineWidth: 6).frame(width: 60, height: 60)
                Circle()
                    .trim(from: 0, to: CGFloat(forensicsCase.riskScore) / 100)
                    .stroke(forensicsCase.riskLevel.color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .frame(width: 60, height: 60)
                    .rotationEffect(.degrees(-90))
                Text("\(forensicsCase.riskScore)")
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundColor(forensicsCase.riskLevel.color)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Risk Score: \(forensicsCase.riskLevel.label)")
                    .font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                Text(forensicsCase.name).font(.system(size: 12)).foregroundColor(Color.white.opacity(0.4)).lineLimit(1)
                Text(forensicsCase.dateRange).font(.system(size: 11)).foregroundColor(Color.white.opacity(0.25))
            }
            Spacer()
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14)
            .fill(forensicsCase.riskLevel.color.opacity(0.05))
            .overlay(RoundedRectangle(cornerRadius: 14)
                .strokeBorder(forensicsCase.riskLevel.color.opacity(0.2), lineWidth: 0.5)))
    }
}

struct ForensicsStat: View {
    let label: String; let value: String; let color: String
    var body: some View {
        VStack(spacing: 4) {
            Text(value).font(.system(size: 20, weight: .black, design: .rounded)).foregroundColor(Color(hex: color))
            Text(label).font(.system(size: 10, weight: .semibold)).foregroundColor(Color(hex: color).opacity(0.5)).tracking(0.5)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(hex: color).opacity(0.06))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(hex: color).opacity(0.12), lineWidth: 0.5)))
    }
}

struct FindingRow: View {
    let finding: Finding
    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(finding.severity.color).frame(width: 6, height: 6)
            Text(finding.title).font(.system(size: 13)).foregroundColor(.white).lineLimit(1)
            Spacer()
            Text(finding.severity.label).font(.system(size: 11)).foregroundColor(finding.severity.color)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(finding.severity.color.opacity(0.04))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(finding.severity.color.opacity(0.1), lineWidth: 0.5)))
    }
}

struct FilterPill: View {
    let label: String; let isSelected: Bool; var color: String = "#00D4FF"; let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(label).font(.system(size: 12, weight: .semibold))
                .foregroundColor(isSelected ? .black : Color(hex: color).opacity(0.7))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Capsule().fill(isSelected ? Color(hex: color) : Color(hex: color).opacity(0.08))
                    .overlay(Capsule().strokeBorder(isSelected ? Color.clear : Color(hex: color).opacity(0.15), lineWidth: 0.5)))
        }
        .buttonStyle(ScaleButtonStyle())
    }
}
