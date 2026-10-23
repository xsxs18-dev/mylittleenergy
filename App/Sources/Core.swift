import SwiftUI
import AudioToolbox

func L(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

func LF(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: NSLocalizedString(key, comment: ""), arguments: arguments)
}

enum VX {
    static let dir: String = VXDataDirectory()
    static let statusPath = dir + "/status.plist"
    static let historyPath = dir + "/history.bin"
    static let sessionsPath = dir + "/sessions.json"
    static let healthPath = dir + "/health.json"
    static let hudPath = dir + "/hud.plist"
    static let springBoardStatusPath = dir + "/springboard.plist"
    static let groupID = "group.com.xsxs18.mylittleenergy"

    static let notifySettings = "com.xsxs18.mylittleenergy.settings"
    static let notifyLive = "com.xsxs18.mylittleenergy.live"
    static let notifyCommand = "com.xsxs18.mylittleenergy.command"
    static let notifyStatus = "com.xsxs18.mylittleenergy.status"
    static let notifyLiveMode = "com.xsxs18.mylittleenergy.livemode"
    static let notifySpringBoardStatus = "com.xsxs18.mylittleenergy.sbstatus"
    static let notifySpringBoardTest = "com.xsxs18.mylittleenergy.sbtest"

    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }
}

enum Notify {
    static func post(_ name: String) {
        VXPost(name)
    }

    static func post(_ name: String, state: UInt64) {
        VXPostState(name, state)
    }

    static func state(_ name: String) -> UInt64 {
        VXGetState(name)
    }

    @discardableResult
    static func observe(_ name: String, _ handler: @escaping (UInt64) -> Void) -> Int32 {
        VXObserve(name, handler)
    }

    static func command(_ type: Int, value: Int = 0) {
        let sequence = Int(Date().timeIntervalSince1970 * 10) & 0xFFFF
        VXPostState(VX.notifyCommand, VXMessagePack(type, value, sequence))
    }

    static func springBoardTest(_ test: Int) {
        VXPostState(VX.notifySpringBoardTest, UInt64(test))
    }
}

func anyHashable(_ dictionary: [String: Any]) -> [AnyHashable: Any] {
    var result: [AnyHashable: Any] = [:]
    for (key, value) in dictionary { result[key] = value }
    return result
}

func stringKeyed(_ dictionary: [AnyHashable: Any]?) -> [String: Any] {
    var result: [String: Any] = [:]
    for (key, value) in dictionary ?? [:] {
        if let key = key as? String { result[key] = value }
    }
    return result
}

func readPlist(_ path: String) -> [String: Any] {
    stringKeyed(VXReadPlist(path))
}

// MARK: - Colors

extension Color {
    init(hex: String, fallback: Color = .green) {
        let value = VXParseHexColor(hex)
        if value < 0 {
            self = fallback
        } else {
            self.init(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
        }
    }

    var hexString: String {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        UIColor(self).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        let clamp: (CGFloat) -> Int = { Int((max(0, min(1, $0)) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", clamp(red), clamp(green), clamp(blue))
    }
}

enum Palette {
    static let accents: [String] = ["#32D74B", "#0A84FF", "#5E5CE6", "#BF5AF2", "#FF375F", "#FF9F0A", "#FFD60A", "#64D2FF"]

    static func level(_ level: Int, accent: Color) -> Color {
        if level <= 10 { return .red }
        if level <= 20 { return .orange }
        return accent
    }

    static func temperature(_ celsius: Double) -> Color {
        if !celsius.isFinite { return .gray }
        if celsius >= 40 { return .red }
        if celsius >= 35 { return .orange }
        if celsius <= 5 { return .cyan }
        return .teal
    }

    static func health(_ percent: Double) -> Color {
        if !percent.isFinite { return .gray }
        if percent >= 85 { return .green }
        if percent >= 80 { return .yellow }
        return .orange
    }
}

// MARK: - Formatting

enum Fmt {
    static var fahrenheit: Bool { SettingsStore.shared.int("tempUnit") == 1 }

    static func temperature(_ celsius: Double, decimals: Int = 1) -> String {
        guard celsius.isFinite else { return "–" }
        let value = fahrenheit ? celsius * 9 / 5 + 32 : celsius
        return String(format: "%.\(decimals)f %@", value, fahrenheit ? "°F" : "°C")
    }

    static func temperatureValue(_ celsius: Double) -> Double {
        fahrenheit ? celsius * 9 / 5 + 32 : celsius
    }

    static var temperatureUnit: String { fahrenheit ? "°F" : "°C" }

    static func watts(_ watts: Double, signed: Bool = true) -> String {
        guard watts.isFinite else { return "–" }
        let value = signed ? watts : abs(watts)
        return String(format: abs(value) >= 10 ? "%.1f W" : "%.2f W", value)
    }

    static func volts(_ volts: Double) -> String {
        volts.isFinite ? String(format: "%.3f V", volts) : "–"
    }

    static func milliamps(_ value: Int) -> String {
        "\(value) mA"
    }

    static func mAh(_ value: Int) -> String {
        value < 0 ? "–" : "\(value) mAh"
    }

    static func percent(_ value: Double, decimals: Int = 1) -> String {
        value.isFinite ? String(format: "%.\(decimals)f %%", value) : "–"
    }

    static func duration(minutes: Int) -> String {
        guard minutes >= 0 else { return "–" }
        let hours = minutes / 60
        let rest = minutes % 60
        return hours > 0 ? LF("%ld h %ld min", hours, rest) : LF("%ld min", rest)
    }

    static func duration(seconds: Double) -> String {
        duration(minutes: Int(seconds / 60))
    }

    static func date(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter.string(from: date)
    }

    static func time(_ date: Date) -> String {
        DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .short)
    }

    static func day(_ date: Date) -> String {
        DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .none)
    }
}

// MARK: - System sounds

enum Sounds {
    static let base = "/System/Library/Audio/UISounds"
    private static var cache: [String: SystemSoundID] = [:]

    static func all() -> [String] {
        guard let enumerator = FileManager.default.enumerator(atPath: base) else { return [] }
        var sounds: [String] = []
        while let path = enumerator.nextObject() as? String {
            if path.hasSuffix(".caf") { sounds.append(path) }
        }
        return sounds.sorted { displayName($0).localizedStandardCompare(displayName($1)) == .orderedAscending }
    }

    static func displayName(_ path: String) -> String {
        if path.isEmpty { return L("None") }
        let name = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        let folder = (path as NSString).deletingLastPathComponent
        let pretty = name.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ").capitalized
        return folder.isEmpty ? pretty : "\(pretty) (\(folder))"
    }

    static func play(_ path: String) {
        guard !path.isEmpty else { return }
        let full = path.hasPrefix("/") ? path : base + "/" + path
        if let sound = cache[full] {
            AudioServicesPlaySystemSound(sound)
            return
        }
        var sound: SystemSoundID = 0
        guard AudioServicesCreateSystemSoundID(URL(fileURLWithPath: full) as CFURL, &sound) == 0 else { return }
        cache[full] = sound
        AudioServicesPlaySystemSound(sound)
    }
}

// MARK: - Haptics

enum Haptics {
    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
