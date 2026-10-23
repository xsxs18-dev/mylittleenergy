import SwiftUI
import Charts

struct HistoryView: View {
    @EnvironmentObject private var battery: BatteryStore
    @EnvironmentObject private var settings: SettingsStore
    @State private var range: HistoryRange = .day
    @State private var selectedSession: ChargeSession?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Picker(L("Range"), selection: $range) {
                        ForEach(HistoryRange.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    let samples = battery.samples(in: range)
                    if samples.count < 2 {
                        EmptyHistory()
                    } else {
                        LevelChart(samples: samples, accent: settings.accent)
                        StatsGrid(samples: samples, range: range)
                        TemperatureChart(samples: samples)
                        PowerChart(samples: samples)
                    }
                    if battery.health.count > 1 {
                        HealthChart(entries: battery.health)
                    }
                    SessionsCard(sessions: battery.sessions, current: battery.currentSession, select: { selectedSession = $0 })
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationTitle(L("History"))
            .accentTint()
            .refreshable { battery.loadFiles(throttled: false) }
            .sheet(item: $selectedSession) { session in
                SessionDetailView(session: session)
                    .presentationDetents([.medium, .large])
                    .accentTint()
            }
        }
    }
}

private struct ChartCard<Content: View>: View {
    let title: String
    let symbol: String
    let tint: Color
    var trailing: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(title, systemImage: symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
                Spacer()
                if let trailing {
                    Text(trailing)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            content()
        }
        .card()
    }
}

private struct LevelChart: View {
    let samples: [Sample]
    let accent: Color

    var body: some View {
        ChartCard(title: L("Battery Level"), symbol: "battery.75", tint: accent, trailing: samples.last.map { "\($0.level)%" }) {
            Chart {
                ForEach(Array(samples.enumerated()), id: \.offset) { _, sample in
                    AreaMark(x: .value(L("Time"), sample.time), y: .value("%", sample.level))
                        .foregroundStyle(LinearGradient(colors: [accent.opacity(0.4), accent.opacity(0.03)], startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value(L("Time"), sample.time), y: .value("%", sample.level))
                        .foregroundStyle(accent)
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 2.2))
                }
                ForEach(Array(chargingSpans.enumerated()), id: \.offset) { _, span in
                    RectangleMark(xStart: .value("start", span.0), xEnd: .value("end", span.1), yStart: .value("low", 0), yEnd: .value("high", 100))
                        .foregroundStyle(Color.yellow.opacity(0.1))
                }
            }
            .chartYScale(domain: 0...100)
            .chartYAxis { AxisMarks(values: [0, 25, 50, 75, 100]) }
            .frame(height: 190)
            HStack(spacing: 14) {
                Label(L("Charging"), systemImage: "square.fill")
                    .foregroundStyle(Color.yellow.opacity(0.6))
                Spacer()
            }
            .font(.caption)
        }
    }

    // Stretches of time the device was plugged in, drawn behind the level line.
    private var chargingSpans: [(Date, Date)] {
        var spans: [(Date, Date)] = []
        var start: Date?
        for sample in samples {
            if sample.plugged, start == nil { start = sample.time }
            if !sample.plugged, let begin = start {
                spans.append((begin, sample.time))
                start = nil
            }
        }
        if let begin = start, let last = samples.last { spans.append((begin, last.time)) }
        return spans
    }
}

private struct TemperatureChart: View {
    let samples: [Sample]

    var body: some View {
        let values = samples.filter { $0.temperature.isFinite }
        let maximum = values.map(\.temperature).max() ?? .nan
        ChartCard(title: L("Temperature"), symbol: "thermometer.medium", tint: .orange, trailing: maximum.isFinite ? LF("max %@", Fmt.temperature(maximum)) : nil) {
            Chart(Array(values.enumerated()), id: \.offset) { _, sample in
                LineMark(x: .value(L("Time"), sample.time), y: .value(Fmt.temperatureUnit, Fmt.temperatureValue(sample.temperature)))
                    .foregroundStyle(LinearGradient(colors: [.teal, .orange, .red], startPoint: .bottom, endPoint: .top))
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 2))
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .frame(height: 140)
        }
    }
}

private struct PowerChart: View {
    let samples: [Sample]

    var body: some View {
        let peak = samples.map(\.power).max() ?? 0
        ChartCard(title: L("Power"), symbol: "bolt.fill", tint: .yellow, trailing: peak > 0 ? LF("peak %@", Fmt.watts(peak)) : nil) {
            Chart(Array(samples.enumerated()), id: \.offset) { _, sample in
                BarMark(x: .value(L("Time"), sample.time), y: .value("W", sample.power))
                    .foregroundStyle(sample.power >= 0 ? Color.yellow : Color.orange.opacity(0.7))
            }
            .frame(height: 120)
            Text(L("Above zero the battery charges, below zero it powers the device."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct HealthChart: View {
    let entries: [HealthEntry]

    var body: some View {
        let values = entries.filter { $0.health.isFinite }
        ChartCard(title: L("Battery Health"), symbol: "heart.fill", tint: .pink, trailing: values.last.map { Fmt.percent($0.health) }) {
            Chart(values) { entry in
                LineMark(x: .value(L("Day"), entry.day), y: .value("%", entry.health))
                    .foregroundStyle(Color.pink)
                    .interpolationMethod(.monotone)
                PointMark(x: .value(L("Day"), entry.day), y: .value("%", entry.health))
                    .foregroundStyle(Color.pink)
                    .symbolSize(values.count > 40 ? 0 : 18)
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .frame(height: 140)
            if let first = values.first, let last = values.last, first.id != last.id {
                Text(LF("%@ since %@, %ld cycles", Fmt.percent(last.health - first.health), Fmt.day(first.day), max(0, last.cycles - first.cycles)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct StatsGrid: View {
    let samples: [Sample]
    let range: HistoryRange
    @EnvironmentObject private var battery: BatteryStore

    var body: some View {
        let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        let temperatures = samples.map(\.temperature).filter(\.isFinite)
        let average = temperatures.isEmpty ? Double.nan : temperatures.reduce(0, +) / Double(temperatures.count)
        let pluggedShare = Double(samples.filter(\.plugged).count) / Double(max(samples.count, 1))
        LazyVGrid(columns: columns, spacing: 12) {
            MetricCard(title: L("Drain"), symbol: "arrow.down.right", tint: .orange,
                       value: battery.dischargeRate(in: range).map { String(format: "%.1f %%/h", $0) } ?? "–",
                       caption: L("While unplugged"))
            MetricCard(title: L("Full Battery Lasts"), symbol: "hourglass", tint: .blue,
                       value: battery.estimatedRuntime(in: range).map { Fmt.duration(minutes: Int($0 * 60)) } ?? "–",
                       caption: L("At this drain"))
            MetricCard(title: L("Average Temperature"), symbol: "thermometer.medium", tint: Palette.temperature(average),
                       value: Fmt.temperature(average),
                       caption: nil)
            MetricCard(title: L("Plugged In"), symbol: "powerplug.fill", tint: .green,
                       value: String(format: "%.0f %%", pluggedShare * 100),
                       caption: L("Of the time"))
        }
    }
}

private struct SessionsCard: View {
    let sessions: [ChargeSession]
    let current: ChargeSession?
    let select: (ChargeSession) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(L("Charging Sessions"), systemImage: "bolt.batteryblock")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.green)
            if let current {
                Button { select(current) } label: { SessionRow(session: current, live: true) }
                    .buttonStyle(.plain)
            }
            if sessions.isEmpty && current == nil {
                Text(L("Charging sessions appear here after you charge your device."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(sessions.prefix(30)) { session in
                Divider()
                Button { select(session) } label: { SessionRow(session: session, live: false) }
                    .buttonStyle(.plain)
            }
        }
        .card()
    }
}

private struct SessionRow: View {
    let session: ChargeSession
    let live: Bool

    var body: some View {
        HStack(spacing: 12) {
            IconTile(symbol: session.wireless ? "wave.3.right" : "bolt.fill", color: live ? .green : .gray, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(session.startLevel)% → \(session.endLevel)%")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                Text(live ? L("Charging now") : Fmt.date(session.start))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Fmt.duration(seconds: session.duration))
                    .font(.subheadline)
                    .monospacedDigit()
                if session.averagePower > 0 {
                    Text(Fmt.watts(session.averagePower))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}

struct SessionDetailView: View {
    let session: ChargeSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ValueRow(title: L("Start"), value: Fmt.date(session.start))
                    ValueRow(title: L("End"), value: Fmt.date(session.end))
                    ValueRow(title: L("Duration"), value: Fmt.duration(seconds: session.duration))
                    ValueRow(title: L("Level"), value: "\(session.startLevel)% → \(session.endLevel)%")
                }
                Section {
                    ValueRow(title: L("Energy Charged"), value: String(format: "%.2f Wh", session.energy))
                    ValueRow(title: L("Average Power"), value: session.averagePower > 0 ? Fmt.watts(session.averagePower) : "–")
                    ValueRow(title: L("Peak Power"), value: Fmt.watts(session.peakPower))
                    ValueRow(title: L("Highest Temperature"), value: Fmt.temperature(session.maxTemperature))
                    if session.heldSeconds > 0 {
                        ValueRow(title: L("Held by Charge Limit"), value: Fmt.duration(seconds: session.heldSeconds))
                    }
                }
                Section(L("Charger")) {
                    ValueRow(title: L("Name"), value: session.charger ?? "–")
                    if let manufacturer = session.manufacturer { ValueRow(title: L("Manufacturer"), value: manufacturer) }
                    ValueRow(title: L("Rated Power"), value: session.adapterWatts > 0 ? "\(Int(session.adapterWatts)) W" : "–")
                    ValueRow(title: L("Wireless"), value: session.wireless ? L("Yes") : L("No"))
                }
            }
            .navigationTitle(L("Charging Session"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(L("Done")) { dismiss() } }
            }
        }
    }
}

private struct EmptyHistory: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(L("No History Yet"))
                .font(.headline)
            Text(L("The MyLittleEnergy service records the battery every minute. Graphs show up after a few samples."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .card()
    }
}
