import SwiftUI

struct ModulesView: View {
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink { StatusBarSettingsView() } label: {
                        ModuleRow(title: L("Status Bar"), subtitle: statusBarSummary, symbol: "menubar.rectangle", color: .blue)
                    }
                    NavigationLink { BatteryIconSettingsView() } label: {
                        ModuleRow(title: L("Battery Icon"), subtitle: iconSummary, symbol: "battery.75", color: .green)
                    }
                    NavigationLink { HUDSettingsView() } label: {
                        ModuleRow(title: L("Live HUD"), subtitle: onOff("hudEnabled"), symbol: "rectangle.inset.topright.filled", color: .indigo)
                    }
                    NavigationLink { AnimationSettingsView() } label: {
                        ModuleRow(title: L("Charging Animation"), subtitle: onOff("animEnabled"), symbol: "sparkles", color: .orange)
                    }
                } header: {
                    Text(L("Look"))
                }

                Section {
                    NavigationLink { AlertsView() } label: {
                        ModuleRow(title: L("Alerts & Sounds"), subtitle: alertsSummary, symbol: "bell.badge.fill", color: .red)
                    }
                    NavigationLink { AutomationView() } label: {
                        ModuleRow(title: L("Automation"), subtitle: automationSummary, symbol: "wand.and.stars", color: .purple)
                    }
                } header: {
                    Text(L("React"))
                }

                Section {
                    NavigationLink { WidgetsInfoView() } label: {
                        ModuleRow(title: L("Widgets & Control Center"), subtitle: L("Home Screen, Lock Screen, toggle"), symbol: "square.grid.3x3.square", color: .teal)
                    }
                } header: {
                    Text(L("Everywhere"))
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(L("Modules"))
            .accentTint()
        }
    }

    private func onOff(_ key: String) -> String {
        settings.bool(key) ? L("On") : L("Off")
    }

    private var statusBarSummary: String {
        switch settings.int("sbMode") {
        case 1: return L("Two lines under the time")
        case 2: return L("Replaces the time")
        case 3: return L("Next to the time")
        default: return L("Off")
        }
    }

    private var iconSummary: String {
        switch settings.int("iconMode") {
        case 1: return L("Custom color")
        case 2: return L("Color by level")
        default: return settings.bool("iconChargingCustom") ? L("Custom charging color") : L("System")
        }
    }

    private var alertsSummary: String {
        guard settings.bool("alertsEnabled") else { return L("Off") }
        let levels = settings.dictionaries("alertLevels").filter { ($0["enabled"] as? NSNumber)?.boolValue ?? false }.count
        return levels == 1 ? L("1 level alert") : LF("%ld level alerts", levels)
    }

    private var automationSummary: String {
        let rules = settings.dictionaries("rules").filter { ($0["enabled"] as? NSNumber)?.boolValue ?? false }.count
        return rules == 0 ? L("No rules") : rules == 1 ? L("1 rule") : LF("%ld rules", rules)
    }
}

// MARK: - Fields

struct FieldToggles: View {
    let key: String
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        Toggle(isOn: settings.flag(key, Int(VXFieldPercent))) { Label(L("Percentage"), systemImage: "percent") }
        Toggle(isOn: settings.flag(key, Int(VXFieldPower))) { Label(L("Power (W)"), systemImage: "bolt.fill") }
        Toggle(isOn: settings.flag(key, Int(VXFieldTemperature))) { Label(L("Temperature"), systemImage: "thermometer.medium") }
        Toggle(isOn: settings.flag(key, Int(VXFieldTime))) { Label(L("Time Remaining"), systemImage: "hourglass") }
        Toggle(isOn: settings.flag(key, Int(VXFieldAdapter))) { Label(L("Charger Watts"), systemImage: "powerplug.fill") }
        Toggle(isOn: settings.flag(key, Int(VXFieldHealth))) { Label(L("Health"), systemImage: "heart.fill") }
    }
}

// MARK: - Status bar

struct StatusBarSettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var battery: BatteryStore

    var body: some View {
        List {
            Section {
                StatusBarPreview()
                    .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
            }
            Section {
                Picker(L("Style"), selection: settings.integer("sbMode")) {
                    Text(L("Off")).tag(0)
                    Text(L("Two Lines")).tag(1)
                    Text(L("Replace Time")).tag(2)
                    Text(L("Next to Time")).tag(3)
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text(L("Style"))
            }
            if settings.int("sbMode") != 0 {
                Section {
                    FieldToggles(key: "sbFields")
                } header: {
                    Text(L("Show"))
                } footer: {
                    Text(L("Keep it to one or two values, the status bar has little room on devices with a notch or Dynamic Island."))
                }
                Section {
                    Toggle(L("Only While Charging"), isOn: settings.toggle("sbOnlyCharging"))
                } footer: {
                    Text(L("Changes show up in every app right away, no respring needed."))
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(L("Status Bar"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct StatusBarPreview: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var battery: BatteryStore

    var body: some View {
        let mode = settings.int("sbMode")
        HStack {
            Group {
                switch mode {
                case 1:
                    VStack(spacing: -1) {
                        Text(Fmt.time(Date())).font(.system(size: 13, weight: .semibold))
                        Text(info).font(.system(size: 9, weight: .semibold)).monospacedDigit()
                    }
                case 2:
                    Text(info).font(.system(size: 13, weight: .semibold)).monospacedDigit()
                case 3:
                    HStack(spacing: 4) {
                        Text(Fmt.time(Date())).font(.system(size: 16, weight: .semibold))
                        Text(info).font(.system(size: 11, weight: .semibold)).monospacedDigit()
                    }
                default:
                    Text(Fmt.time(Date())).font(.system(size: 16, weight: .semibold))
                }
            }
            .frame(minWidth: 70)
            Spacer()
            Capsule().fill(Color.black).frame(width: 96, height: 28)
            Spacer()
            HStack(spacing: 5) {
                Image(systemName: "cellularbars")
                Image(systemName: "wifi")
                BatteryGlyph(level: Double(battery.info?.level ?? 80) / 100, fill: .green)
                    .scaleEffect(0.55)
                    .frame(width: 34)
            }
            .font(.system(size: 13, weight: .semibold))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Color(uiColor: .systemBackground)))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(Color.primary.opacity(0.08)))
    }

    private var info: String {
        let separator = settings.int("sbMode") == 3 ? " " : " · "
        let live = VXLiveUnpack(Notify.state(VX.notifyLive))
        var look = VXLookFromSettings(anyHashable(settings.values))
        look.statusBarOnlyCharging = false
        let preview = live.valid.boolValue ? live : (battery.info?.live(withHeld: false) ?? live)
        return VXStatusBarText(look, preview, separator) ?? L("Nothing selected")
    }
}

// MARK: - Battery icon

struct BatteryIconSettingsView: View {
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        List {
            Section {
                HStack(spacing: 26) {
                    Spacer()
                    VStack(spacing: 6) {
                        BatteryGlyph(level: 0.72, fill: previewColor(level: 0.72))
                        Text("72%").font(.caption).foregroundStyle(.secondary)
                    }
                    VStack(spacing: 6) {
                        BatteryGlyph(level: 0.45, fill: settings.bool("iconChargingCustom") ? settings.color("iconChargingColor").wrappedValue : .green, charging: true)
                        Text(L("Charging")).font(.caption).foregroundStyle(.secondary)
                    }
                    VStack(spacing: 6) {
                        BatteryGlyph(level: 0.12, fill: .red)
                        Text("12%").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 8)
            }
            Section {
                Picker(L("Color"), selection: settings.integer("iconMode")) {
                    Text(L("System")).tag(0)
                    Text(L("Custom")).tag(1)
                    Text(L("By Level")).tag(2)
                }
                .pickerStyle(.segmented)
                if settings.int("iconMode") == 1 {
                    ColorPicker(L("Battery Color"), selection: settings.color("iconColor"), supportsOpacity: false)
                }
                Toggle(L("Custom Charging Color"), isOn: settings.toggle("iconChargingCustom"))
                if settings.bool("iconChargingCustom") {
                    ColorPicker(L("Charging Color"), selection: settings.color("iconChargingColor"), supportsOpacity: false)
                }
            } header: {
                Text(L("Fill"))
            } footer: {
                Text(L("By Level fades from red to green as the battery fills. Low Power Mode keeps its yellow."))
            }
            Section {
                SliderRow(title: L("Red Below"), value: settings.rounded("iconLowThreshold"), range: 5...50, step: 1) { "\(Int($0))%" }
            } footer: {
                Text(L("iOS turns the icon red at 20%."))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(L("Battery Icon"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func previewColor(level: Double) -> Color {
        switch settings.int("iconMode") {
        case 1: return settings.color("iconColor").wrappedValue
        case 2: return Color(hue: 0.33 * level, saturation: 0.82, brightness: 0.92)
        default: return .primary
        }
    }
}

// MARK: - HUD

struct HUDSettingsView: View {
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        List {
            Section {
                Toggle(isOn: settings.toggle("hudEnabled")) {
                    Label(L("Live HUD"), systemImage: "rectangle.inset.topright.filled")
                }
            } footer: {
                Text(L("A small floating readout above every app. Drag it anywhere, tap it to open MyLittleEnergy, long press to switch between compact and large."))
            }
            if settings.bool("hudEnabled") {
                Section {
                    Picker(L("Show"), selection: settings.integer("hudWhen")) {
                        Text(L("Always")).tag(0)
                        Text(L("While Charging")).tag(1)
                    }
                    Picker(L("Layout"), selection: settings.integer("hudSize")) {
                        Text(L("Compact")).tag(0)
                        Text(L("Large")).tag(1)
                    }
                    SliderRow(title: L("Opacity"), value: settings.number("hudOpacity"), range: 0.3...1, step: 0.05) { "\(Int($0 * 100))%" }
                    Toggle(L("Hide on Lock Screen"), isOn: settings.toggle("hudHideLock"))
                }
                Section {
                    FieldToggles(key: "hudFields")
                } header: {
                    Text(L("Values"))
                }
                Section {
                    Button(L("Reset Position")) {
                        try? FileManager.default.removeItem(atPath: VX.hudPath)
                        Notify.post(VX.notifySettings)
                        Haptics.success()
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(L("Live HUD"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Charging animation

struct AnimationSettingsView: View {
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        List {
            Section {
                Toggle(isOn: settings.toggle("animEnabled")) {
                    Label(L("Charging Animation"), systemImage: "sparkles")
                }
            } footer: {
                Text(L("Plays on the Lock Screen when you connect a charger."))
            }
            Section {
                HStack(spacing: 12) {
                    ForEach(0..<3) { style in
                        AnimationStyleTile(style: style, selected: settings.int("animStyle") == style)
                            .onTapGesture {
                                Haptics.tap()
                                settings.set("animStyle", style)
                            }
                    }
                }
                .padding(.vertical, 6)
                SliderRow(title: L("Duration"), value: settings.rounded("animDuration"), range: 2...10, step: 1) { LF("%ld s", Int($0)) }
                Toggle(L("Show Watts and Time to Full"), isOn: settings.toggle("animDetails"))
                Toggle(L("Hide the iOS Charging View"), isOn: settings.toggle("animHideNative"))
            } header: {
                Text(L("Style"))
            }
            Section {
                Button {
                    settings.flush()
                    Notify.springBoardTest(Int(VXSBTestAnimation))
                } label: {
                    Label(L("Preview Now"), systemImage: "play.fill")
                }
            } footer: {
                Text(L("The preview plays over this screen. Tap it to close."))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(L("Charging Animation"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AnimationStyleTile: View {
    let style: Int
    let selected: Bool
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.black)
                switch style {
                case 1:
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.white.opacity(0.85), lineWidth: 2)
                        .frame(width: 30, height: 50)
                        .overlay(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(settings.accent)
                                .frame(width: 26, height: 32)
                                .padding(2)
                        }
                case 2:
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(settings.accent)
                        .shadow(color: settings.accent, radius: 8)
                default:
                    Circle()
                        .trim(from: 0, to: 0.72)
                        .stroke(settings.accent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 46, height: 46)
                }
            }
            .frame(height: 84)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(selected ? settings.accent : Color.clear, lineWidth: 3)
            )
            Text([L("Ring"), L("Wave"), L("Pulse")][style])
                .font(.caption.weight(selected ? .semibold : .regular))
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }
}

// MARK: - Widgets and Control Center

struct WidgetsInfoView: View {
    private var hasCCSupport: Bool {
        FileManager.default.fileExists(atPath: VXJailbreakPath("/Library/MobileSubstrate/DynamicLibraries/CCSupport.dylib"))
            || FileManager.default.fileExists(atPath: VXJailbreakPath("/usr/lib/TweakInject/CCSupport.dylib"))
    }

    var body: some View {
        List {
            Section {
                InfoBanner(symbol: "apps.iphone", text: L("Long press the Home Screen, tap Edit → Add Widget and search for MyLittleEnergy. There are widgets for the battery level, battery health and a 24 hour chart."), tint: .teal)
                InfoBanner(symbol: "lock.iphone", text: L("Lock Screen widgets: long press the Lock Screen, tap Customize → Lock Screen and add the MyLittleEnergy gauge or line."), tint: .teal)
            } header: {
                Text(L("Widgets"))
            } footer: {
                Text(L("iOS refreshes widgets on its own schedule, usually every 15 minutes. Opening MyLittleEnergy refreshes them right away."))
            }
            Section {
                HStack {
                    Label(L("CCSupport"), systemImage: "switch.2")
                    Spacer()
                    Text(hasCCSupport ? L("Installed") : L("Not Installed"))
                        .foregroundStyle(hasCCSupport ? Color.green : Color.secondary)
                }
                InfoBanner(symbol: "info.circle.fill", text: L("The Charge Limit toggle for Control Center needs CCSupport by opa334. Add it in Settings → Control Center after installing CCSupport."), tint: .blue)
            } header: {
                Text(L("Control Center"))
            }
            Section {
                ValueRow(title: "mylittleenergy://full", value: L("Charge to 100% once"))
                ValueRow(title: "mylittleenergy://limit/on", value: L("Turn the limit on"))
                ValueRow(title: "mylittleenergy://limit/off", value: L("Turn the limit off"))
            } header: {
                Text(L("Shortcuts"))
            } footer: {
                Text(L("Use these links with the Open URL action in Shortcuts, for example in a personal automation."))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(L("Widgets & Control Center"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
