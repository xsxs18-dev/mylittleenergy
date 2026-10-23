import SwiftUI

struct OverviewView: View {
    let selectTab: (Int) -> Void
    @EnvironmentObject private var battery: BatteryStore
    @EnvironmentObject private var settings: SettingsStore
    @State private var showSettings = false

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let info = battery.info {
                        HeroCard(info: info)
                        if !battery.daemonRunning || !battery.tweakLoaded {
                            SetupWarning()
                        }
                        QuickActions(info: info, selectTab: selectTab)
                        LazyVGrid(columns: columns, spacing: 12) {
                            metricCards(info)
                        }
                        NavigationLink {
                            DetailsView()
                        } label: {
                            HStack {
                                IconTile(symbol: "list.bullet.rectangle.fill", color: .indigo)
                                Text(L("All Battery Data"))
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .card()
                        }
                        .buttonStyle(.plain)
                    } else {
                        UnreadableBattery()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("MyLittleEnergy")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape.fill") }
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView().accentTint() }
            .accentTint()
        }
    }

    @ViewBuilder
    private func metricCards(_ info: VXBatteryInfo) -> some View {
        let accent = settings.accent
        MetricCard(
            title: L("Health"), symbol: "heart.fill", tint: Palette.health(info.health),
            value: Fmt.percent(info.health),
            caption: info.healthFromSystem ? L("Maximum capacity (iOS)") : L("Full charge vs. design")
        ) {
            if battery.health.count > 1 {
                Sparkline(points: battery.health.suffix(60).enumerated().map { ChartPoint(id: $0.offset, x: $0.element.day, y: $0.element.health) }, tint: Palette.health(info.health))
            }
        }
        MetricCard(
            title: L("Temperature"), symbol: "thermometer.medium", tint: Palette.temperature(info.temperature),
            value: Fmt.temperature(info.temperature),
            caption: temperatureCaption(info.temperature)
        ) {
            Sparkline(points: battery.live.map { ChartPoint(id: $0.id, x: $0.time, y: Fmt.temperatureValue($0.temperature)) }, tint: Palette.temperature(info.temperature))
        }
        MetricCard(
            title: L("Power"), symbol: "bolt.fill", tint: info.batteryPower >= 0 ? .yellow : .orange,
            value: Fmt.watts(info.batteryPower),
            caption: info.batteryPower >= 0 ? L("Into the battery") : L("Out of the battery")
        ) {
            Sparkline(points: battery.live.map { ChartPoint(id: $0.id, x: $0.time, y: $0.power) }, tint: .yellow)
        }
        MetricCard(
            title: L("Cycles"), symbol: "arrow.triangle.2.circlepath", tint: .purple,
            value: info.cycleCount >= 0 ? "\(info.cycleCount)" : "–",
            caption: info.designCycleCount > 0 ? LF("Rated for %ld", info.designCycleCount) : L("Charge cycles")
        )
        MetricCard(
            title: L("Capacity"), symbol: "battery.100", tint: accent,
            value: Fmt.mAh(info.fullChargeCapacity),
            caption: info.designCapacity > 0 ? LF("Design %ld mAh", info.designCapacity) : nil
        )
        MetricCard(
            title: L("Charge"), symbol: "battery.50", tint: accent,
            value: Fmt.mAh(info.currentCapacity),
            caption: L("Stored right now")
        )
        MetricCard(
            title: L("Voltage"), symbol: "waveform.path.ecg", tint: .blue,
            value: Fmt.volts(info.voltage),
            caption: info.cellVoltages.count > 1 ? LF("%ld cells", info.cellVoltages.count) : L("Battery voltage")
        )
        MetricCard(
            title: L("Current"), symbol: "arrow.left.arrow.right", tint: .cyan,
            value: Fmt.milliamps(info.amperage),
            caption: LF("Average %ld mA", info.averageAmperage)
        )
    }

    private func temperatureCaption(_ celsius: Double) -> String {
        guard celsius.isFinite else { return L("Not reported") }
        if celsius >= 40 { return L("Hot, avoid charging") }
        if celsius >= 35 { return L("Warm") }
        if celsius <= 5 { return L("Cold") }
        return L("Normal")
    }
}

// MARK: - Hero

private struct HeroCard: View {
    let info: VXBatteryInfo
    @EnvironmentObject private var battery: BatteryStore
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        let tint = Palette.level(info.level, accent: settings.accent)
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [tint.opacity(0.28), .clear], center: .center, startRadius: 10, endRadius: 150))
                    .frame(width: 270, height: 270)
                BatteryRing(level: Double(info.level) / 100, tint: tint)
                    .frame(width: 196, height: 196)
                VStack(spacing: 2) {
                    if info.plugged {
                        Image(systemName: battery.held ? "pause.circle.fill" : "bolt.fill")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(battery.held ? Color.teal : Color.yellow)
                    }
                    Text("\(info.level)%")
                        .font(.system(size: 54, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text(Fmt.watts(info.batteryPower))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .frame(height: 230)
            VStack(spacing: 4) {
                Text(statusTitle)
                    .font(.headline)
                if let subtitle = statusSubtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .card(padding: 16)
    }

    private var statusTitle: String {
        if !info.plugged { return L("On Battery") }
        switch battery.limitState {
        case "holding": return LF("Held at %ld%%", info.level)
        case "bypass": return L("Running on Battery (charger bypassed)")
        case "heat": return L("Charging Paused, Battery Warm")
        default: break
        }
        if info.fullyCharged { return L("Fully Charged") }
        if info.charging { return L("Charging") }
        return L("Not Charging")
    }

    private var statusSubtitle: String? {
        var parts: [String] = []
        let minutes = battery.minutesLeft(info)
        if minutes > 0 {
            if info.charging {
                let target = battery.chargeTarget
                parts.append(target < 100 ? LF("%ld%% in %@", target, Fmt.duration(minutes: minutes)) : LF("Full in %@", Fmt.duration(minutes: minutes)))
            } else if !info.plugged {
                parts.append(LF("%@ left", Fmt.duration(minutes: minutes)))
            }
        }
        if info.plugged {
            if let name = info.adapterName ?? info.adapterDescription, name != "batt" {
                parts.append(info.adapterWatts > 0 ? "\(name) · \(Int(info.adapterWatts)) W" : name)
            } else if info.adapterWatts > 0 {
                parts.append(LF("%ld W charger", Int(info.adapterWatts)))
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }
}

// MARK: - Quick actions

private struct QuickActions: View {
    let info: VXBatteryInfo
    let selectTab: (Int) -> Void
    @EnvironmentObject private var battery: BatteryStore
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        HStack(spacing: 12) {
            Button {
                Haptics.tap()
                settings.set("limitEnabled", !settings.bool("limitEnabled"), immediately: true)
            } label: {
                quickLabel(
                    symbol: settings.bool("limitEnabled") ? "bolt.badge.checkmark.fill" : "bolt.slash.fill",
                    title: L("Charge Limit"),
                    value: settings.bool("limitEnabled") ? "\(settings.int("limitMax"))%" : L("Off"),
                    active: settings.bool("limitEnabled")
                )
            }
            .buttonStyle(.plain)
            if settings.bool("limitEnabled") || battery.fullOnce {
                Button {
                    Haptics.tap()
                    Notify.command(Int(battery.fullOnce ? VXCommandCancelFullOnce : VXCommandFullOnce))
                } label: {
                    quickLabel(
                        symbol: "battery.100.bolt",
                        title: battery.fullOnce ? L("Cancel Full Charge") : L("Charge to 100%"),
                        value: battery.fullOnce ? L("Active") : L("Once"),
                        active: battery.fullOnce
                    )
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    Haptics.tap()
                    settings.set("heatEnabled", !settings.bool("heatEnabled"), immediately: true)
                } label: {
                    quickLabel(
                        symbol: "thermometer.sun.fill",
                        title: L("Heat Protection"),
                        value: settings.bool("heatEnabled") ? Fmt.temperature(settings.double("heatMax"), decimals: 0) : L("Off"),
                        active: settings.bool("heatEnabled")
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func quickLabel(symbol: String, title: String, value: String, active: Bool) -> some View {
        HStack(spacing: 10) {
            IconTile(symbol: symbol, color: active ? settings.accent : .gray, size: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(value)
                    .font(.headline)
                    .monospacedDigit()
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .card(padding: 12)
    }
}

// MARK: - Problems

private struct SetupWarning: View {
    @EnvironmentObject private var battery: BatteryStore

    var body: some View {
        NavigationLink {
            DiagnosticsView()
        } label: {
            InfoBanner(
                symbol: "exclamationmark.triangle.fill",
                text: battery.springBoardSafeMode
                    ? L("SpringBoard did not complete MyLittleEnergy initialization. Integration stays disabled until you retry from Diagnostics. Tap to copy a report.")
                    : !battery.daemonRunning
                    ? L("The MyLittleEnergy service isn't running, so the charge limit, history and alerts are paused. Tap for diagnostics.")
                    : L("The SpringBoard part of MyLittleEnergy hasn't reported yet. Respring once after installing. Tap for diagnostics.")
            )
            .card()
        }
        .buttonStyle(.plain)
    }
}

private struct UnreadableBattery: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "battery.0")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(L("Battery Not Readable"))
                .font(.headline)
            Text(L("MyLittleEnergy can't read the battery registry. Make sure the device is jailbroken and MyLittleEnergy was installed with its entitlements."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            NavigationLink(L("Diagnostics")) { DiagnosticsView() }
                .prominentButton()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .card()
    }
}
