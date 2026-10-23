import SwiftUI

struct ChargingView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var battery: BatteryStore

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LimitStatusCard()
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

                LimitSection()
                HeatSection()
                ScheduleSection()

                Section {
                    InfoBanner(symbol: "info.circle.fill", text: L("Turn off Optimized Battery Charging in Settings → Battery while you use the charge limit, otherwise iOS and MyLittleEnergy fight over the charger."), tint: .blue)
                    if UIDevice.current.userInterfaceIdiom == .phone {
                        InfoBanner(symbol: "iphone.gen3", text: L("iPhone 15 and newer also have a built-in 80% limit. MyLittleEnergy gives you any limit between 50 and 100% plus heat protection and schedules."), tint: .gray)
                    }
                    NavigationLink {
                        DiagnosticsView()
                    } label: {
                        Label(L("Test Charge Control"), systemImage: "stethoscope")
                    }
                } header: {
                    Text(L("Good to Know"))
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(L("Charging"))
            .accentTint()
        }
    }
}

private struct LimitStatusCard: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var battery: BatteryStore

    var body: some View {
        let info = battery.info
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                IconTile(symbol: symbol, color: color, size: 46)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            if settings.bool("limitEnabled") {
                LimitBar(level: info?.level ?? 0, limit: settings.int("limitMax"), resume: settings.int("limitResume"), tint: settings.accent)
            }
            if settings.bool("limitEnabled") || battery.fullOnce {
                Button {
                    Haptics.tap()
                    Notify.command(Int(battery.fullOnce ? VXCommandCancelFullOnce : VXCommandFullOnce))
                } label: {
                    Label(battery.fullOnce ? L("Cancel Full Charge") : L("Charge to 100% Once"), systemImage: battery.fullOnce ? "arrow.uturn.backward" : "battery.100.bolt")
                        .frame(maxWidth: .infinity)
                }
                .prominentButton()
                .controlSize(.large)
            }
        }
        .card(padding: 16)
    }

    private var symbol: String {
        switch battery.limitState {
        case "holding": return "pause.circle.fill"
        case "bypass": return "powerplug"
        case "heat": return "thermometer.high"
        case "full-once", "schedule": return "battery.100.bolt"
        case "charging": return "bolt.fill"
        default: return settings.bool("limitEnabled") ? "bolt.badge.checkmark.fill" : "bolt.slash.fill"
        }
    }

    private var color: Color {
        switch battery.limitState {
        case "holding", "bypass": return .teal
        case "heat": return .orange
        case "charging", "full-once", "schedule": return .green
        default: return settings.bool("limitEnabled") ? settings.accent : .gray
        }
    }

    private var title: String {
        if !settings.bool("limitEnabled") && !settings.bool("heatEnabled") { return L("Charge Limit Off") }
        switch battery.limitState {
        case "holding": return LF("Holding at %ld%%", battery.info?.level ?? 0)
        case "bypass": return L("Running on Battery")
        case "heat": return L("Paused, Battery Warm")
        case "full-once": return L("Charging to 100% Once")
        case "schedule": return L("Scheduled Full Charge")
        case "charging": return LF("Charging to %ld%%", settings.int("limitMax"))
        case "on-battery": return LF("Limit %ld%%", settings.int("limitMax"))
        default: return L("Charge Limit On")
        }
    }

    private var subtitle: String {
        if !battery.daemonRunning { return L("The MyLittleEnergy service isn't running.") }
        if !settings.bool("limitEnabled") && !settings.bool("heatEnabled") {
            return L("Charges like normal. Turn the limit on to keep the battery healthier.")
        }
        switch battery.limitState {
        case "holding": return LF("The charger powers your device, the battery rests. Charging starts again at %ld%%.", settings.int("limitResume"))
        case "bypass": return LF("The charger is bypassed until the battery drops to %ld%%.", settings.int("limitResume"))
        case "heat": return L("Charging continues when the battery cools down.")
        case "full-once": return L("Back to your limit after you unplug.")
        case "schedule": return L("The limit is lifted until the schedule window ends.")
        case "on-battery": return L("Plug in to charge up to your limit.")
        default:
            return settings.bool("limitEnabled")
                ? LF("Stops at %ld%% and starts again at %ld%%.", settings.int("limitMax"), settings.int("limitResume"))
                : L("Charges like normal. Turn the limit on to keep the battery healthier.")
        }
    }
}

private struct LimitBar: View {
    let level: Int
    let limit: Int
    let resume: Int
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { proxy in
                let width = proxy.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule()
                        .fill(tint.gradient)
                        .frame(width: max(8, width * CGFloat(level) / 100))
                    Rectangle()
                        .fill(Color.primary.opacity(0.6))
                        .frame(width: 2, height: 22)
                        .offset(x: width * CGFloat(limit) / 100 - 1)
                    Rectangle()
                        .fill(Color.primary.opacity(0.3))
                        .frame(width: 2, height: 22)
                        .offset(x: width * CGFloat(resume) / 100 - 1)
                }
            }
            .frame(height: 16)
            HStack {
                Text("\(level)%").monospacedDigit()
                Spacer()
                Text(LF("resume %ld%% · stop %ld%%", resume, limit)).monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

private struct LimitSection: View {
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        Section {
            Toggle(isOn: settings.toggle("limitEnabled")) {
                Label(L("Charge Limit"), systemImage: "bolt.badge.checkmark")
            }
            if settings.bool("limitEnabled") {
                SliderRow(title: L("Stop Charging At"), value: maxBinding, range: 50...100, step: 1) { "\(Int($0))%" }
                SliderRow(title: L("Start Again At"), value: resumeBinding, range: 20...99, step: 1) { "\(Int($0))%" }
                Picker(selection: settings.integer("limitMode")) {
                    Text(L("Pause Charging")).tag(0)
                    Text(L("Run on Battery")).tag(1)
                } label: {
                    Label(L("At the Limit"), systemImage: "arrow.triangle.branch")
                }
            }
        } header: {
            Text(L("Limit"))
        } footer: {
            if settings.bool("limitEnabled") {
                Text(settings.int("limitMode") == 0
                     ? L("Pause Charging: the charger keeps powering the device and the battery stays at the limit.")
                     : L("Run on Battery: the charger is bypassed, the battery powers the device down to the start level, then charges again. Good against swelling when the device stays plugged in all day."))
            }
        }
    }

    // The resume level always stays below the stop level.
    private var maxBinding: Binding<Double> {
        Binding(get: { Double(settings.int("limitMax")) }, set: { value in
            let limit = Int(value.rounded())
            settings.set("limitMax", limit)
            if settings.int("limitResume") >= limit { settings.set("limitResume", limit - 1) }
        })
    }

    private var resumeBinding: Binding<Double> {
        Binding(get: { Double(settings.int("limitResume")) }, set: { value in
            settings.set("limitResume", min(Int(value.rounded()), settings.int("limitMax") - 1))
        })
    }
}

private struct HeatSection: View {
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        Section {
            Toggle(isOn: settings.toggle("heatEnabled")) {
                Label(L("Heat Protection"), systemImage: "thermometer.sun")
            }
            if settings.bool("heatEnabled") {
                SliderRow(title: L("Pause Above"), value: settings.rounded("heatMax"), range: 32...48, step: 1) { Fmt.temperature($0, decimals: 0) }
            }
        } header: {
            Text(L("Temperature"))
        } footer: {
            Text(L("Charging pauses while the battery is this warm and continues 2 °C below. Heat ages a battery faster than anything else."))
        }
    }
}

private struct ScheduleSection: View {
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        Section {
            Toggle(isOn: settings.toggle("scheduleEnabled")) {
                Label(L("Full Charge Schedule"), systemImage: "alarm")
            }
            if settings.bool("scheduleEnabled") {
                DatePicker(L("Charge to 100% From"), selection: timeBinding, displayedComponents: .hourAndMinute)
                Picker(L("For"), selection: settings.integer("scheduleWindow")) {
                    ForEach([60, 120, 180, 240, 360, 480], id: \.self) { minutes in
                        Text(Fmt.duration(minutes: minutes)).tag(minutes)
                    }
                }
            }
        } header: {
            Text(L("Schedule"))
        } footer: {
            Text(L("Keeps the limit overnight and lifts it shortly before you get up, so the battery is full when you need it."))
        }
    }

    private var timeBinding: Binding<Date> {
        Binding(get: {
            Calendar.current.date(bySettingHour: settings.int("scheduleHour"), minute: settings.int("scheduleMinute"), second: 0, of: Date()) ?? Date()
        }, set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            settings.set("scheduleHour", parts.hour ?? 6)
            settings.set("scheduleMinute", parts.minute ?? 0)
        })
    }
}
