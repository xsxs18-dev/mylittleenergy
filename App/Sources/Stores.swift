import SwiftUI
import WidgetKit

// MARK: - Settings

// settings.plist, shared with the daemon and the tweak. Edits are written after
// a short pause so sliders don't rewrite the file on every step.
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @Published private(set) var values: [String: Any] = [:]
    private var pendingSave: DispatchWorkItem?

    private init() {
        reload()
        Notify.observe(VX.notifySettings) { [weak self] _ in
            guard let self, self.pendingSave == nil else { return }
            self.reload()
        }
    }

    func reload() {
        values = stringKeyed(VXReadSettings())
    }

    func bool(_ key: String) -> Bool { (values[key] as? NSNumber)?.boolValue ?? false }
    func int(_ key: String) -> Int { (values[key] as? NSNumber)?.intValue ?? 0 }
    func double(_ key: String) -> Double { (values[key] as? NSNumber)?.doubleValue ?? 0 }
    func string(_ key: String) -> String { values[key] as? String ?? "" }
    func dictionaries(_ key: String) -> [[String: Any]] {
        (values[key] as? [Any])?.compactMap { $0 as? [String: Any] } ?? []
    }

    var accent: Color { Color(hex: string("accentColor")) }

    func set(_ key: String, _ value: Any, immediately: Bool = false) {
        values[key] = value
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.flush() }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (immediately ? 0 : 0.35), execute: work)
    }

    func flush() {
        pendingSave = nil
        _ = VXWriteSettings(anyHashable(values))
        WidgetCenter.shared.reloadAllTimelines()
    }

    func resetAll() {
        values = stringKeyed(VXSettingsDefaults())
        set("groupPath", FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: VX.groupID)?.path ?? "", immediately: true)
    }

    // MARK: Bindings

    func toggle(_ key: String) -> Binding<Bool> {
        Binding(get: { self.bool(key) }, set: { self.set(key, $0) })
    }

    func integer(_ key: String) -> Binding<Int> {
        Binding(get: { self.int(key) }, set: { self.set(key, $0) })
    }

    func number(_ key: String) -> Binding<Double> {
        Binding(get: { self.double(key) }, set: { self.set(key, $0) })
    }

    // Sliders work on Double, the daemon reads whole numbers.
    func rounded(_ key: String) -> Binding<Double> {
        Binding(get: { Double(self.int(key)) }, set: { self.set(key, Int($0.rounded())) })
    }

    func color(_ key: String) -> Binding<Color> {
        Binding(get: { Color(hex: self.string(key)) }, set: { self.set(key, $0.hexString) })
    }

    func flag(_ key: String, _ bit: Int) -> Binding<Bool> {
        Binding(get: { self.int(key) & bit != 0 }, set: { on in
            let value = self.int(key)
            self.set(key, on ? value | bit : value & ~bit)
        })
    }
}

// MARK: - History models

struct Sample {
    let time: Date
    let level: Int
    let flags: UInt8
    let temperature: Double
    let voltage: Double
    let amperage: Int
    let power: Double
    let adapterPower: Double
    let currentCapacity: Int
    let fullCapacity: Int
    let cycles: Int
    let health: Double

    var charging: Bool { flags & 1 != 0 }
    var plugged: Bool { flags & 2 != 0 }
    var held: Bool { flags & 8 != 0 }
    var screenOn: Bool { flags & 64 != 0 }

    static let size = 24

    static func parse(_ data: Data) -> [Sample] {
        let count = data.count / size
        var samples: [Sample] = []
        samples.reserveCapacity(count)
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            for index in 0..<count {
                let o = index * size
                let temperature = raw.loadUnaligned(fromByteOffset: o + 6, as: Int16.self)
                samples.append(Sample(
                    time: Date(timeIntervalSince1970: TimeInterval(raw.loadUnaligned(fromByteOffset: o, as: UInt32.self))),
                    level: Int(raw.load(fromByteOffset: o + 4, as: UInt8.self)),
                    flags: raw.load(fromByteOffset: o + 5, as: UInt8.self),
                    temperature: temperature == Int16.min ? .nan : Double(temperature) / 100,
                    voltage: Double(raw.loadUnaligned(fromByteOffset: o + 8, as: UInt16.self)) / 1000,
                    amperage: Int(raw.loadUnaligned(fromByteOffset: o + 10, as: Int16.self)),
                    power: Double(raw.loadUnaligned(fromByteOffset: o + 12, as: Int16.self)) / 100,
                    adapterPower: Double(raw.loadUnaligned(fromByteOffset: o + 14, as: UInt16.self)) / 10,
                    currentCapacity: Int(raw.loadUnaligned(fromByteOffset: o + 16, as: UInt16.self)),
                    fullCapacity: Int(raw.loadUnaligned(fromByteOffset: o + 18, as: UInt16.self)),
                    cycles: Int(raw.loadUnaligned(fromByteOffset: o + 20, as: UInt16.self)),
                    health: Double(raw.loadUnaligned(fromByteOffset: o + 22, as: UInt16.self)) / 100
                ))
            }
        }
        return samples
    }
}

struct ChargeSession: Identifiable {
    let start: Date
    let end: Date
    let startLevel: Int
    let endLevel: Int
    let maxTemperature: Double
    let energy: Double
    let peakPower: Double
    let heldSeconds: Double
    let charger: String?
    let manufacturer: String?
    let adapterWatts: Double
    let wireless: Bool

    var id: Double { start.timeIntervalSince1970 }
    var duration: TimeInterval { end.timeIntervalSince(start) }
    var averagePower: Double {
        let charging = duration - heldSeconds
        return charging > 60 ? energy / (charging / 3600) : 0
    }

    init?(_ dictionary: [String: Any]) {
        guard let start = (dictionary["start"] as? NSNumber)?.doubleValue else { return nil }
        let number: (String) -> Double = { (dictionary[$0] as? NSNumber)?.doubleValue ?? 0 }
        self.start = Date(timeIntervalSince1970: start)
        end = Date(timeIntervalSince1970: max(number("end"), start))
        startLevel = Int(number("startLevel"))
        endLevel = Int(number("endLevel"))
        maxTemperature = number("maxTemp")
        energy = number("energy")
        peakPower = number("peakPower")
        heldSeconds = number("heldSeconds")
        charger = dictionary["charger"] as? String
        manufacturer = dictionary["manufacturer"] as? String
        adapterWatts = number("adapterWatts")
        wireless = (dictionary["wireless"] as? NSNumber)?.boolValue ?? false
    }
}

struct HealthEntry: Identifiable {
    let day: Date
    let health: Double
    let full: Int
    let design: Int
    let cycles: Int
    var id: Double { day.timeIntervalSince1970 }

    init?(_ dictionary: [String: Any]) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        guard let text = dictionary["day"] as? String, let day = formatter.date(from: text) else { return nil }
        self.day = day
        health = (dictionary["health"] as? NSNumber)?.doubleValue ?? .nan
        full = (dictionary["full"] as? NSNumber)?.intValue ?? -1
        design = (dictionary["design"] as? NSNumber)?.intValue ?? -1
        cycles = (dictionary["cycles"] as? NSNumber)?.intValue ?? -1
    }
}

struct LivePoint: Identifiable {
    let id: Int
    let time: Date
    let power: Double
    let temperature: Double
}

enum HistoryRange: Int, CaseIterable, Identifiable {
    case day, week, month, quarter
    var id: Int { rawValue }

    var title: String {
        switch self {
        case .day: return L("24 Hours")
        case .week: return L("7 Days")
        case .month: return L("30 Days")
        case .quarter: return L("90 Days")
        }
    }

    var seconds: TimeInterval {
        switch self {
        case .day: return 86400
        case .week: return 7 * 86400
        case .month: return 30 * 86400
        case .quarter: return 90 * 86400
        }
    }

    // Charts stay fast with roughly a thousand points.
    var bucket: TimeInterval {
        switch self {
        case .day: return 120
        case .week: return 600
        case .month: return 3600
        case .quarter: return 3 * 3600
        }
    }
}

// MARK: - Battery

final class BatteryStore: ObservableObject {
    static let shared = BatteryStore()

    @Published private(set) var info: VXBatteryInfo?
    @Published private(set) var samples: [Sample] = []
    @Published private(set) var sessions: [ChargeSession] = []
    @Published private(set) var health: [HealthEntry] = []
    @Published private(set) var daemon: [String: Any] = [:]
    @Published private(set) var springBoard: [String: Any] = [:]
    @Published private(set) var live: [LivePoint] = []

    private var timer: Timer?
    private var lastLiveRequest = Date.distantPast
    private var lastFileLoad = Date.distantPast
    private var liveCounter = 0
    private var loading = false
    private var statusLoading = false
    private var statusReloadPending = false
    private var fileSignature = ""

    private init() {
        Notify.observe(VX.notifyStatus) { [weak self] _ in self?.loadFiles(throttled: true) }
        Notify.observe(VX.notifySpringBoardStatus) { [weak self] _ in
            self?.springBoard = readPlist(VX.springBoardStatusPath)
        }
    }

    func activate() {
        refresh()
        loadFiles(throttled: false)
        springBoard = readPlist(VX.springBoardStatusPath)
        Notify.springBoardTest(Int(VXSBTestStatus))
        Notify.command(Int(VXCommandWriteStatus))
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func deactivate() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        let current = VXBatteryInfo.current()
        info = current
        if let current {
            liveCounter += 1
            live.append(LivePoint(id: liveCounter, time: current.date, power: current.batteryPower, temperature: current.temperature))
            if live.count > 180 { live.removeFirst(live.count - 180) }
        }
        // The daemon samples every 2 s while the app asks for it.
        if Date().timeIntervalSince(lastLiveRequest) > 15 {
            lastLiveRequest = Date()
            Notify.post(VX.notifyLiveMode, state: UInt64(Date().timeIntervalSince1970 + 30))
        }
        if Date().timeIntervalSince(lastFileLoad) > 30 { loadFiles(throttled: false) }
    }

    func loadFiles(throttled: Bool) {
        // Command acknowledgements must not wait for the history throttle.
        loadDaemonStatus()
        if loading || (throttled && Date().timeIntervalSince(lastFileLoad) < 5) { return }
        loading = true
        lastFileLoad = Date()
        let previousSignature = fileSignature
        DispatchQueue.global(qos: .userInitiated).async {
            // The service reports its status every few seconds, but the history files only change
            // about once a minute; parsing up to 90 days of samples each time would cost battery.
            let signature = Self.signature(of: [VX.historyPath, VX.sessionsPath, VX.healthPath])
            if signature == previousSignature {
                DispatchQueue.main.async { self.loading = false }
                return
            }
            let samples = Sample.parse((try? Data(contentsOf: URL(fileURLWithPath: VX.historyPath))) ?? Data())
            let sessions = Self.readJSONArray(VX.sessionsPath).compactMap(ChargeSession.init).reversed()
            let health = Self.readJSONArray(VX.healthPath).compactMap(HealthEntry.init)
            DispatchQueue.main.async {
                self.samples = samples
                self.sessions = Array(sessions)
                self.health = health
                self.fileSignature = signature
                self.loading = false
            }
        }
    }

    private func loadDaemonStatus() {
        if statusLoading {
            statusReloadPending = true
            return
        }
        statusLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let daemon = readPlist(VX.statusPath)
            DispatchQueue.main.async {
                self.daemon = daemon
                self.statusLoading = false
                if self.statusReloadPending {
                    self.statusReloadPending = false
                    self.loadDaemonStatus()
                }
            }
        }
    }

    // Size and modification time of each file; changes whenever the service writes one of them.
    private static func signature(of paths: [String]) -> String {
        paths.map { path in
            let attributes = try? FileManager.default.attributesOfItem(atPath: path)
            let size = (attributes?[.size] as? NSNumber)?.int64Value ?? -1
            let modified = (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
            return "\(size):\(modified)"
        }.joined(separator: "|")
    }

    private static func readJSONArray(_ path: String) -> [[String: Any]] {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let array = try? JSONSerialization.jsonObject(with: data) as? [Any] else { return [] }
        return array.compactMap { $0 as? [String: Any] }
    }

    // MARK: Derived values

    var daemonRunning: Bool {
        guard let updated = (daemon["updated"] as? NSNumber)?.doubleValue else { return false }
        return Date().timeIntervalSince1970 - updated < 180
    }

    var tweakLoaded: Bool {
        (springBoard["time"] as? NSNumber) != nil && !springBoardSafeMode
    }

    // SpringBoard froze or crashed right after its last start with MyLittleEnergy and now runs without it.
    var springBoardSafeMode: Bool {
        (springBoard["safeMode"] as? NSNumber)?.boolValue ?? false
    }

    var limitState: String { daemon["state"] as? String ?? "" }
    var chargeTarget: Int { (daemon["chargeTarget"] as? NSNumber)?.intValue ?? 100 }

    // Same estimate as the status bar, HUD and widgets: the service's, from the recent drain.
    // Without the service it is worked out here from the history file.
    func minutesLeft(_ info: VXBatteryInfo) -> Int {
        let live = VXLiveUnpack(Notify.state(VX.notifyLive))
        if daemonRunning && live.valid.boolValue && live.level == info.level { return live.minutes }
        let now = Date().timeIntervalSince1970
        let entries: [[NSNumber]] = samples.suffix(800).filter { $0.time.timeIntervalSince1970 >= now - 12 * 3600 }.map {
            [NSNumber(value: $0.time.timeIntervalSince1970), NSNumber(value: $0.level), NSNumber(value: $0.plugged)]
        }
        let target = settingsTarget
        return VXEstimateMinutes(info, VXDrainPerHour(entries, now), target)
    }

    private var settingsTarget: Int {
        let settings = SettingsStore.shared
        return settings.bool("limitEnabled") && !fullOnce ? settings.int("limitMax") : 100
    }
    var held: Bool { ((daemon["applied"] as? NSNumber)?.intValue ?? 0) != 0 }
    var fullOnce: Bool { (daemon["fullOnce"] as? NSNumber)?.boolValue ?? false }

    var currentSession: ChargeSession? {
        (daemon["session"] as? [String: Any]).flatMap(ChargeSession.init)
    }

    func samples(in range: HistoryRange) -> [Sample] {
        let start = Date().addingTimeInterval(-range.seconds)
        var result: [Sample] = []
        var lastBucket = -1
        for sample in samples where sample.time >= start {
            let bucket = Int(sample.time.timeIntervalSince1970 / range.bucket)
            if bucket == lastBucket { continue }
            lastBucket = bucket
            result.append(sample)
        }
        return result
    }

    // %/h while unplugged, from consecutive samples on battery.
    func dischargeRate(in range: HistoryRange) -> Double? {
        let start = Date().addingTimeInterval(-range.seconds)
        var drop = 0.0
        var time = 0.0
        var previous: Sample?
        for sample in samples where sample.time >= start {
            defer { previous = sample }
            guard let last = previous, !last.plugged, !sample.plugged else { continue }
            let elapsed = sample.time.timeIntervalSince(last.time)
            guard elapsed > 0, elapsed < 900 else { continue }
            drop += Double(last.level - sample.level)
            time += elapsed
        }
        return time > 1800 ? drop / (time / 3600) : nil
    }

    func estimatedRuntime(in range: HistoryRange) -> Double? {
        guard let rate = dischargeRate(in: range), rate > 0.1 else { return nil }
        return 100 / rate
    }

    func csv() -> URL? {
        var lines = ["time,level,charging,plugged,held,temperature_c,voltage_v,amperage_ma,power_w,adapter_w,capacity_mah,full_mah,cycles,health"]
        let formatter = ISO8601DateFormatter()
        for sample in samples {
            lines.append([
                formatter.string(from: sample.time), "\(sample.level)", sample.charging ? "1" : "0", sample.plugged ? "1" : "0", sample.held ? "1" : "0",
                sample.temperature.isFinite ? String(format: "%.2f", sample.temperature) : "",
                String(format: "%.3f", sample.voltage), "\(sample.amperage)", String(format: "%.2f", sample.power), String(format: "%.1f", sample.adapterPower),
                "\(sample.currentCapacity)", "\(sample.fullCapacity)", "\(sample.cycles)", String(format: "%.2f", sample.health),
            ].joined(separator: ","))
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("MyLittleEnergy-History.csv")
        do {
            try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }
}
