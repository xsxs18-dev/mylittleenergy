import SwiftUI
import WidgetKit
import Charts

func L(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

func LF(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: NSLocalizedString(key, comment: ""), arguments: arguments)
}

// MARK: - Data

struct LevelPoint: Identifiable {
    let id: Int
    let time: Date
    let level: Int
}

// widget.json, written by the daemon about once a minute.
struct Snapshot {
    var time = Date()
    var level = 0
    var charging = false
    var plugged = false
    var full = false
    var held = false
    var temperature: Double?
    var power = 0.0
    var minutes = -1
    var health: Double?
    var cycles = -1
    var limitEnabled = false
    var limitMax = 80
    var fahrenheit = false
    var accent = Color.green
    var levels: [LevelPoint] = []
    var placeholder = false

    static let preview: Snapshot = {
        var snapshot = Snapshot()
        snapshot.level = 76
        snapshot.charging = true
        snapshot.plugged = true
        snapshot.temperature = 31.4
        snapshot.power = 12.6
        snapshot.minutes = 48
        snapshot.health = 91.2
        snapshot.cycles = 412
        snapshot.limitEnabled = true
        snapshot.placeholder = true
        let now = Date()
        snapshot.levels = (0..<48).map { index in
            let level = 40 + Int(36 * sin(Double(index) / 48 * .pi))
            return LevelPoint(id: index, time: now.addingTimeInterval(Double(index - 48) * 1800), level: level)
        }
        return snapshot
    }()

    static func load() -> Snapshot {
        var paths: [String] = []
        if let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.xsxs18.mylittleenergy") {
            paths.append(group.appendingPathComponent("widget.json").path)
        }
        let dataDirectory: String = VXDataDirectory()
        paths.append(dataDirectory + "/widget.json")
        var best: Snapshot?
        for path in paths {
            guard let data = FileManager.default.contents(atPath: path),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            let snapshot = Snapshot(json: json)
            if best == nil || snapshot.time > best!.time { best = snapshot }
        }
        var snapshot = best ?? Snapshot()
        // The live notify state is newer than the file while the daemon samples quickly.
        let live = VXLiveUnpack(VXGetState("com.xsxs18.mylittleenergy.live"))
        if live.valid.boolValue {
            snapshot.level = live.level
            snapshot.charging = live.charging.boolValue
            snapshot.plugged = live.external.boolValue
            snapshot.full = live.full.boolValue
            snapshot.held = live.held.boolValue
            snapshot.power = live.power
            snapshot.temperature = live.temperature
            snapshot.minutes = live.minutes
            if live.health > 0 { snapshot.health = Double(live.health) }
            if best == nil { snapshot.time = Date() }
        } else if best == nil {
            snapshot.placeholder = true
        }
        return snapshot
    }

    init() {}

    init(json: [String: Any]) {
        let number: (String) -> NSNumber? = { json[$0] as? NSNumber }
        time = Date(timeIntervalSince1970: number("time")?.doubleValue ?? 0)
        level = number("level")?.intValue ?? 0
        charging = number("charging")?.boolValue ?? false
        plugged = number("plugged")?.boolValue ?? false
        full = number("full")?.boolValue ?? false
        held = number("held")?.boolValue ?? false
        temperature = number("temperature")?.doubleValue
        power = number("power")?.doubleValue ?? 0
        minutes = number("minutes")?.intValue ?? -1
        health = number("health")?.doubleValue
        cycles = number("cycles")?.intValue ?? -1
        limitEnabled = number("limitEnabled")?.boolValue ?? false
        limitMax = number("limitMax")?.intValue ?? 80
        fahrenheit = number("fahrenheit")?.boolValue ?? false
        accent = Self.color(json["accent"] as? String) ?? .green
        let raw = json["levels"] as? [[NSNumber]] ?? []
        levels = raw.enumerated().compactMap { index, pair in
            guard pair.count == 2 else { return nil }
            return LevelPoint(id: index, time: Date(timeIntervalSince1970: pair[0].doubleValue), level: pair[1].intValue)
        }
    }

    static func color(_ hex: String?) -> Color? {
        guard let hex else { return nil }
        let value = VXParseHexColor(hex)
        guard value >= 0 else { return nil }
        return Color(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }

    var tint: Color {
        if level <= 10 { return .red }
        if level <= 20 { return .orange }
        return accent
    }

    var temperatureText: String {
        guard let temperature else { return "–" }
        return fahrenheit ? String(format: "%.0f °F", temperature * 9 / 5 + 32) : String(format: "%.1f °C", temperature)
    }

    var powerText: String {
        String(format: abs(power) >= 10 ? "%.1f W" : "%.2f W", power)
    }

    var timeText: String? {
        guard minutes > 0 else { return nil }
        return minutes >= 60 ? "\(minutes / 60):" + String(format: "%02d", minutes % 60) : LF("%ld min", minutes)
    }

    var status: String {
        if !plugged { return timeText.map { LF("%@ left", $0) } ?? L("On Battery") }
        if held { return L("Held by limit") }
        if full { return L("Fully Charged") }
        if charging { return timeText.map { LF("Full in %@", $0) } ?? L("Charging") }
        return L("Not Charging")
    }
}

// MARK: - Timeline

struct Entry: TimelineEntry {
    let date: Date
    let snapshot: Snapshot
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry {
        Entry(date: Date(), snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(Entry(date: Date(), snapshot: context.isPreview ? .preview : Snapshot.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let entry = Entry(date: Date(), snapshot: Snapshot.load())
        // Plugged in, the level changes faster, so iOS is asked to come back sooner.
        let minutes = entry.snapshot.plugged ? 5.0 : 15.0
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(minutes * 60))))
    }
}

extension View {
    // containerBackground only exists in the iOS 17 SDK; widgets linked against an older SDK run in compatibility mode.
    @ViewBuilder
    func widgetBackground() -> some View {
        #if compiler(>=5.9)
        if #available(iOS 17.0, *) {
            containerBackground(for: .widget) { Color(uiColor: .systemBackground) }
        } else {
            background(Color(uiColor: .systemBackground))
        }
        #else
        background(Color(uiColor: .systemBackground))
        #endif
    }
}

// MARK: - Views

struct Ring: View {
    let level: Int
    let tint: Color
    var width: CGFloat = 9

    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.18), lineWidth: width)
            Circle()
                .trim(from: 0, to: max(0.01, Double(level) / 100))
                .stroke(tint.gradient, style: StrokeStyle(lineWidth: width, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

struct BatterySmallView: View {
    let snapshot: Snapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                Ring(level: snapshot.level, tint: snapshot.tint, width: 10)
                VStack(spacing: 0) {
                    if snapshot.plugged {
                        Image(systemName: snapshot.held ? "pause.fill" : "bolt.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(snapshot.held ? Color.teal : Color.yellow)
                    }
                    Text("\(snapshot.level)%")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
            }
            .frame(width: 86, height: 86)
            .frame(maxWidth: .infinity)
            Text(snapshot.status)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text("\(snapshot.powerText) · \(snapshot.temperatureText)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .redacted(reason: snapshot.placeholder ? .placeholder : [])
    }
}

struct BatteryMediumView: View {
    let snapshot: Snapshot

    var body: some View {
        HStack(spacing: 16) {
            BatterySmallView(snapshot: snapshot)
                .frame(width: 120)
            VStack(alignment: .leading, spacing: 8) {
                stat(symbol: "bolt.fill", tint: .yellow, title: L("Power"), value: snapshot.powerText)
                stat(symbol: "thermometer.medium", tint: .orange, title: L("Temperature"), value: snapshot.temperatureText)
                stat(symbol: "heart.fill", tint: .pink, title: L("Health"), value: snapshot.health.map { String(format: "%.1f %%", $0) } ?? "–")
                stat(symbol: "bolt.badge.checkmark.fill", tint: snapshot.accent, title: L("Limit"), value: snapshot.limitEnabled ? "\(snapshot.limitMax)%" : L("Off"))
            }
        }
    }

    private func stat(symbol: String, tint: Color, title: String, value: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 16)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text(value)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
        }
    }
}

struct ChartView: View {
    let snapshot: Snapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(L("Last 24 Hours"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(snapshot.level)%")
                    .font(.headline)
                    .monospacedDigit()
            }
            if snapshot.levels.count > 1 {
                Chart(snapshot.levels) { point in
                    AreaMark(x: .value("t", point.time), y: .value("%", point.level))
                        .foregroundStyle(LinearGradient(colors: [snapshot.accent.opacity(0.45), snapshot.accent.opacity(0.03)], startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("t", point.time), y: .value("%", point.level))
                        .foregroundStyle(snapshot.accent)
                        .interpolationMethod(.monotone)
                }
                .chartYScale(domain: 0...100)
                .chartYAxis { AxisMarks(values: [0, 50, 100]) }
                .chartXAxis(.hidden)
            } else {
                Spacer()
                Text(L("History shows up after a few hours."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
    }
}

struct HealthView: View {
    let snapshot: Snapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: "heart.fill")
                .foregroundStyle(.pink)
                .font(.title3)
            Spacer()
            Text(snapshot.health.map { String(format: "%.1f%%", $0) } ?? "–")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
            Text(L("Battery Health"))
                .font(.caption.weight(.semibold))
            Text(snapshot.cycles >= 0 ? LF("%ld cycles", snapshot.cycles) : " ")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .redacted(reason: snapshot.placeholder ? .placeholder : [])
    }
}

struct AccessoryView: View {
    let snapshot: Snapshot
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: Double(snapshot.level), in: 0...100) {
                Image(systemName: snapshot.plugged ? "bolt.fill" : "battery.75")
            } currentValueLabel: {
                Text("\(snapshot.level)")
                    .monospacedDigit()
            }
            .gaugeStyle(.accessoryCircular)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Image(systemName: snapshot.plugged ? "bolt.fill" : "battery.75")
                    Text("\(snapshot.level)%").font(.headline).monospacedDigit()
                }
                Text(snapshot.status).font(.caption).lineLimit(1)
                Text("\(snapshot.powerText) · \(snapshot.temperatureText)").font(.caption2).monospacedDigit().lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            Text("\(snapshot.plugged ? "⚡︎" : "")\(snapshot.level)% · \(snapshot.temperatureText)")
        }
    }
}

// MARK: - Widgets

struct BatteryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.xsxs18.mylittleenergy.battery", provider: Provider()) { entry in
            BatteryFamilyView(snapshot: entry.snapshot)
            .widgetBackground()
        }
        .configurationDisplayName(L("Battery"))
        .description(L("Level, power, temperature and the charge limit."))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct BatteryFamilyView: View {
    let snapshot: Snapshot
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if family == .systemMedium {
            BatteryMediumView(snapshot: snapshot)
        } else {
            BatterySmallView(snapshot: snapshot)
        }
    }
}

struct ChartWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.xsxs18.mylittleenergy.chart", provider: Provider()) { entry in
            ChartView(snapshot: entry.snapshot)
            .widgetBackground()
        }
        .configurationDisplayName(L("Battery History"))
        .description(L("Your battery level over the last 24 hours."))
        .supportedFamilies([.systemMedium])
    }
}

struct HealthWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.xsxs18.mylittleenergy.health", provider: Provider()) { entry in
            HealthView(snapshot: entry.snapshot)
            .widgetBackground()
        }
        .configurationDisplayName(L("Battery Health"))
        .description(L("Maximum capacity and charge cycles."))
        .supportedFamilies([.systemSmall])
    }
}

struct LockScreenWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.xsxs18.mylittleenergy.lockscreen", provider: Provider()) { entry in
            AccessoryView(snapshot: entry.snapshot)
            .widgetBackground()
        }
        .configurationDisplayName("MyLittleEnergy")
        .description(L("Battery level on the Lock Screen."))
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

@main
struct MyLittleEnergyWidgets: WidgetBundle {
    var body: some Widget {
        BatteryWidget()
        ChartWidget()
        HealthWidget()
        LockScreenWidget()
    }
}
