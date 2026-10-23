import SwiftUI

struct DetailsView: View {
    @EnvironmentObject private var battery: BatteryStore

    var body: some View {
        List {
            if let info = battery.info {
                BatterySection(info: info)
                CapacitySection(info: info)
                ElectricalSection(info: info)
                ChargerSection(info: info)
                if !info.cellVoltages.isEmpty || !info.qmax.isEmpty { CellsSection(info: info) }
                if let lifetime = info.lifetime, !lifetime.isEmpty { LifetimeSection(lifetime: stringKeyed(lifetime)) }
                if let telemetry = info.telemetry, !telemetry.isEmpty { TelemetrySection(telemetry: stringKeyed(telemetry)) }
                Section {
                    NavigationLink(L("Raw Registry Values")) {
                        RawDataView(title: "AppleSmartBattery", dictionary: stringKeyed(info.raw))
                    }
                } footer: {
                    Text(L("Every value the battery driver reports, exactly as iOS sees it."))
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(L("Battery Data"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct BatterySection: View {
    let info: VXBatteryInfo
    @EnvironmentObject private var battery: BatteryStore

    var body: some View {
        Section(L("Battery")) {
            Group {
                ValueRow(title: L("Charge Level"), value: "\(info.level) %", symbol: "battery.75", tint: .green)
                ValueRow(title: L("Health"), value: Fmt.percent(info.health), symbol: "heart.fill", tint: .pink)
                ValueRow(title: L("Cycle Count"), value: info.cycleCount >= 0 ? "\(info.cycleCount)" : "–", symbol: "arrow.triangle.2.circlepath", tint: .purple)
                if info.designCycleCount > 0 {
                    ValueRow(title: L("Rated Cycles"), value: "\(info.designCycleCount)", symbol: "checkmark.seal", tint: .purple)
                }
                ValueRow(title: L("Temperature"), value: Fmt.temperature(info.temperature, decimals: 2), symbol: "thermometer.medium", tint: .orange)
                if info.virtualTemperature.isFinite {
                    ValueRow(title: L("Virtual Temperature"), value: Fmt.temperature(info.virtualTemperature, decimals: 2), symbol: "thermometer.variable.and.figure", tint: .orange)
                }
                ValueRow(title: L("Estimated Time Left"), value: Fmt.duration(minutes: battery.minutesLeft(info)), symbol: "hourglass", tint: .blue)
                ValueRow(title: L("Gauge: Time to Empty"), value: Fmt.duration(minutes: info.timeToEmpty), symbol: "hourglass.bottomhalf.filled", tint: .gray)
                ValueRow(title: L("Gauge: Time to Full"), value: Fmt.duration(minutes: info.timeToFull), symbol: "hourglass.tophalf.filled", tint: .gray)
            }
            Group {
                if let serial = info.serial { ValueRow(title: L("Serial Number"), value: serial, symbol: "number", tint: .gray) }
                if let name = info.deviceName { ValueRow(title: L("Gas Gauge"), value: name, symbol: "cpu", tint: .gray) }
                if let firmware = info.firmware { ValueRow(title: L("Gauge Firmware"), value: firmware, symbol: "gearshape.2", tint: .gray) }
                if let chemistry = info.chemistry { ValueRow(title: L("Chemistry ID"), value: chemistry, symbol: "atom", tint: .gray) }
            }
        }
    }
}

private struct CapacitySection: View {
    let info: VXBatteryInfo

    var body: some View {
        Section {
            ValueRow(title: L("Current Charge"), value: Fmt.mAh(info.currentCapacity))
            ValueRow(title: L("Full Charge Capacity"), value: Fmt.mAh(info.fullChargeCapacity))
            ValueRow(title: L("Nominal Capacity"), value: Fmt.mAh(info.nominalCapacity))
            ValueRow(title: L("Design Capacity"), value: Fmt.mAh(info.designCapacity))
            if info.designCapacity > 0 && info.fullChargeCapacity > 0 {
                ValueRow(title: L("Capacity Lost"), value: Fmt.mAh(max(0, info.designCapacity - info.fullChargeCapacity)))
            }
        } header: {
            Text(L("Capacity"))
        } footer: {
            Text(info.healthFromSystem
                 ? L("Health is the Maximum Capacity iOS shows in Settings.")
                 : L("Health is the nominal charge capacity compared to the design capacity."))
        }
    }
}

private struct ElectricalSection: View {
    let info: VXBatteryInfo

    var body: some View {
        Section(L("Electrical")) {
            ValueRow(title: L("Voltage"), value: Fmt.volts(info.voltage))
            ValueRow(title: L("Current"), value: Fmt.milliamps(info.amperage))
            ValueRow(title: L("Average Current"), value: Fmt.milliamps(info.averageAmperage))
            ValueRow(title: L("Battery Power"), value: Fmt.watts(info.batteryPower))
            if info.systemPowerIn.isFinite { ValueRow(title: L("Power from Charger"), value: Fmt.watts(info.systemPowerIn)) }
            if info.systemLoad.isFinite { ValueRow(title: L("Device Power Use"), value: Fmt.watts(info.systemLoad)) }
        }
    }
}

private struct ChargerSection: View {
    let info: VXBatteryInfo

    var body: some View {
        Section(L("Charging")) {
            ValueRow(title: L("Connected"), value: info.plugged ? L("Yes") : L("No"))
            ValueRow(title: L("Charging"), value: info.charging ? L("Yes") : L("No"))
            ValueRow(title: L("Fully Charged"), value: info.fullyCharged ? L("Yes") : L("No"))
            if info.plugged {
                if let name = info.adapterName { ValueRow(title: L("Charger"), value: name) }
                if let manufacturer = info.adapterManufacturer { ValueRow(title: L("Manufacturer"), value: manufacturer) }
                if let description = info.adapterDescription { ValueRow(title: L("Type"), value: description) }
                if info.adapterWatts > 0 { ValueRow(title: L("Rated Power"), value: "\(Int(info.adapterWatts)) W") }
                if info.adapterVoltage.isFinite { ValueRow(title: L("Charger Voltage"), value: Fmt.volts(info.adapterVoltage)) }
                if info.adapterCurrent >= 0 { ValueRow(title: L("Charger Current"), value: Fmt.milliamps(info.adapterCurrent)) }
                ValueRow(title: L("Wireless"), value: info.adapterWireless ? L("Yes") : L("No"))
            }
            if info.chargingCurrent >= 0 { ValueRow(title: L("Requested Current"), value: Fmt.milliamps(info.chargingCurrent)) }
            if info.chargingVoltage >= 0 { ValueRow(title: L("Requested Voltage"), value: "\(info.chargingVoltage) mV") }
            if info.notChargingReason >= 0 { ValueRow(title: L("Not Charging Reason"), value: info.notChargingReason == 0 ? L("None") : String(format: "0x%lX", info.notChargingReason)) }
            if let inhibited = info.chargeInhibited { ValueRow(title: L("Charge Inhibit Flag"), value: inhibited.boolValue ? L("On") : L("Off")) }
        }
    }
}

private struct CellsSection: View {
    let info: VXBatteryInfo

    var body: some View {
        Section(L("Cells")) {
            ForEach(Array(info.cellVoltages.enumerated()), id: \.offset) { index, voltage in
                ValueRow(title: LF("Cell %ld Voltage", index + 1), value: "\(voltage.intValue) mV")
            }
            ForEach(Array(info.qmax.enumerated()), id: \.offset) { index, qmax in
                ValueRow(title: LF("Cell %ld Qmax", index + 1), value: "\(qmax.intValue) mAh")
            }
        }
    }
}

private struct LifetimeItem: Identifiable {
    let key: String
    let title: String
    let unit: String
    var id: String { key }
}

private struct LifetimeSection: View {
    let lifetime: [String: Any]

    private static let known = [
        LifetimeItem(key: "MaximumTemperature", title: L("Highest Temperature"), unit: "temp"),
        LifetimeItem(key: "MinimumTemperature", title: L("Lowest Temperature"), unit: "temp"),
        LifetimeItem(key: "AverageTemperature", title: L("Average Temperature"), unit: "temp"),
        LifetimeItem(key: "MaximumChargeCurrent", title: L("Highest Charge Current"), unit: "mA"),
        LifetimeItem(key: "MaximumDischargeCurrent", title: L("Highest Discharge Current"), unit: "mA"),
        LifetimeItem(key: "MaximumPackVoltage", title: L("Highest Voltage"), unit: "mV"),
        LifetimeItem(key: "MinimumPackVoltage", title: L("Lowest Voltage"), unit: "mV"),
        LifetimeItem(key: "TotalOperatingTime", title: L("Operating Time"), unit: "h"),
    ]

    var body: some View {
        Section {
            ForEach(Self.known.filter { lifetime[$0.key] is NSNumber }) { item in
                ValueRow(title: item.title, value: format((lifetime[item.key] as? NSNumber)?.doubleValue ?? 0, unit: item.unit))
            }
        } header: {
            Text(L("Lifetime"))
        } footer: {
            Text(L("Extremes the battery recorded since it was made."))
        }
    }

    // Some gauges report tenths of a degree, others whole degrees.
    private func format(_ value: Double, unit: String) -> String {
        switch unit {
        case "temp": return Fmt.temperature(abs(value) > 150 ? value / 10 : value, decimals: 1)
        case "h": return "\(Int(value)) h"
        default: return "\(Int(value)) \(unit)"
        }
    }
}

private struct TelemetrySection: View {
    let telemetry: [String: Any]

    var body: some View {
        Section(L("Power Telemetry")) {
            ForEach(telemetry.keys.sorted(), id: \.self) { key in
                ValueRow(title: key, value: RawValue.describe(telemetry[key]))
            }
        }
    }
}

// MARK: - Raw values

enum RawValue {
    static func describe(_ value: Any?) -> String {
        switch value {
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return number.boolValue ? "true" : "false" }
            return number.stringValue
        case let string as String:
            return string
        case let data as Data:
            if let text = String(data: data, encoding: .utf8), !text.isEmpty, text.allSatisfy({ !$0.isASCII || $0.isPrintable }) { return text }
            return data.prefix(32).map { String(format: "%02X", $0) }.joined(separator: " ") + (data.count > 32 ? " …" : "")
        case let array as [Any]:
            return LF("%ld items", array.count)
        case let dictionary as [String: Any]:
            return LF("%ld values", dictionary.count)
        case nil:
            return "–"
        default:
            return String(describing: value!)
        }
    }

    static func json(_ value: Any) -> Any {
        switch value {
        case let dictionary as [String: Any]: return dictionary.mapValues(json)
        case let array as [Any]: return array.map(json)
        case let data as Data: return data.base64EncodedString()
        case let number as NSNumber: return number
        case let string as String: return string
        default: return String(describing: value)
        }
    }
}

private extension Character {
    var isPrintable: Bool { isASCII && (asciiValue ?? 0) >= 32 && (asciiValue ?? 0) < 127 }
}

struct RawDataView: View {
    let title: String
    let dictionary: [String: Any]
    @State private var search = ""

    var body: some View {
        List {
            ForEach(keys, id: \.self) { key in
                row(key: key, value: dictionary[key])
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $search)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    let object = RawValue.json(dictionary)
                    if let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) {
                        UIPasteboard.general.string = String(data: data, encoding: .utf8)
                        Haptics.success()
                    }
                } label: {
                    Image(systemName: "doc.on.doc")
                }
            }
        }
    }

    private var keys: [String] {
        let all = dictionary.keys.sorted()
        return search.isEmpty ? all : all.filter { $0.localizedCaseInsensitiveContains(search) }
    }

    @ViewBuilder
    private func row(key: String, value: Any?) -> some View {
        if let nested = value as? [String: Any] {
            NavigationLink { RawDataView(title: key, dictionary: nested) } label: { ValueRow(title: key, value: RawValue.describe(value)) }
        } else if let array = value as? [Any], array.contains(where: { $0 is [String: Any] || $0 is [Any] }) {
            NavigationLink {
                RawDataView(title: key, dictionary: Dictionary(uniqueKeysWithValues: array.enumerated().map { (String(format: "%03ld", $0.offset), $0.element) }))
            } label: {
                ValueRow(title: key, value: RawValue.describe(value))
            }
        } else if let array = value as? [Any] {
            ValueRow(title: key, value: array.map { RawValue.describe($0) }.joined(separator: ", "))
        } else {
            ValueRow(title: key, value: RawValue.describe(value))
        }
    }
}
