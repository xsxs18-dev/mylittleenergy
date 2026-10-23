import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var battery: BatteryStore
    @Environment(\.dismiss) private var dismiss
    @State private var confirmClear = false
    @State private var confirmReset = false
    @State private var exportURL: URL?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle(isOn: settings.toggle("enabled")) {
                        Label(L("MyLittleEnergy Enabled"), systemImage: "power")
                    }
                } footer: {
                    Text(L("Turns every module off at once. The battery data stays readable."))
                }

                Section {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 10) {
                        ForEach(Palette.accents, id: \.self) { hex in
                            Circle()
                                .fill(Color(hex: hex))
                                .frame(width: 30, height: 30)
                                .overlay(Circle().stroke(Color.primary, lineWidth: settings.string("accentColor") == hex ? 3 : 0).padding(-3))
                                .onTapGesture {
                                    Haptics.tap()
                                    settings.set("accentColor", hex, immediately: true)
                                }
                        }
                    }
                    .padding(.vertical, 6)
                    Picker(L("Temperature"), selection: settings.integer("tempUnit")) {
                        Text("°C").tag(0)
                        Text("°F").tag(1)
                    }
                } header: {
                    Text(L("Appearance"))
                }

                Section {
                    Picker(L("Record Every"), selection: settings.integer("sampleInterval")) {
                        Text(L("30 Seconds")).tag(30)
                        Text(L("1 Minute")).tag(60)
                        Text(L("2 Minutes")).tag(120)
                        Text(L("5 Minutes")).tag(300)
                    }
                    Picker(L("Keep History For"), selection: settings.integer("retentionDays")) {
                        Text(L("30 Days")).tag(30)
                        Text(L("90 Days")).tag(90)
                        Text(L("180 Days")).tag(180)
                        Text(L("1 Year")).tag(365)
                    }
                    if let exportURL {
                        ShareLink(item: exportURL) {
                            Label(L("Share CSV"), systemImage: "square.and.arrow.up")
                        }
                    } else {
                        Button {
                            exportURL = battery.csv()
                        } label: {
                            Label(L("Export History as CSV"), systemImage: "tablecells")
                        }
                    }
                    Button(role: .destructive) {
                        confirmClear = true
                    } label: {
                        Label(L("Clear History"), systemImage: "trash")
                    }
                } header: {
                    Text(L("History"))
                } footer: {
                    Text(LF("%ld samples, %ld charging sessions stored.", battery.samples.count, battery.sessions.count))
                }

                Section {
                    NavigationLink {
                        DiagnosticsView()
                    } label: {
                        Label(L("Diagnostics"), systemImage: "stethoscope")
                    }
                    Button(role: .destructive) {
                        confirmReset = true
                    } label: {
                        Label(L("Reset All Settings"), systemImage: "arrow.counterclockwise")
                    }
                }

                Section {
                    ValueRow(title: L("Version"), value: VX.version)
                    ValueRow(title: L("Developer"), value: "xsxs18")
                } header: {
                    Text(L("About"))
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(L("Settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(L("Done")) { dismiss() } }
            }
            .confirmationDialog(L("Clear the whole history?"), isPresented: $confirmClear, titleVisibility: .visible) {
                Button(L("Clear History"), role: .destructive) {
                    Notify.command(Int(VXCommandClearHistory))
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { battery.loadFiles(throttled: false) }
                }
            } message: {
                Text(L("Samples, charging sessions and the health log are deleted."))
            }
            .confirmationDialog(L("Reset all settings?"), isPresented: $confirmReset, titleVisibility: .visible) {
                Button(L("Reset"), role: .destructive) { settings.resetAll() }
            } message: {
                Text(L("Every module goes back to its default. Your history stays."))
            }
        }
    }
}

struct DiagnosticsView: View {
    @EnvironmentObject private var battery: BatteryStore
    @EnvironmentObject private var settings: SettingsStore
    @State private var testing = false
    @State private var recoveryMessage: String?

    var body: some View {
        List {
            Section {
                check(L("Battery readable"), battery.info != nil, detail: battery.info.map { LF("%ld values", $0.raw.count) })
                check(L("MyLittleEnergy service running"), battery.daemonRunning, detail: battery.daemon["version"] as? String)
                check(L("Charge control available"), (battery.daemon["controlAvailable"] as? NSNumber)?.boolValue ?? false, detail: nil)
                check(L("SpringBoard tweak loaded"), battery.tweakLoaded, detail: battery.springBoardSafeMode ? L("Safe mode") : battery.springBoard["version"] as? String)
                check(L("Widget data shared"), battery.daemon["groupPath"] != nil, detail: nil)
            } header: {
                Text(L("Status"))
            } footer: {
                if !battery.daemonRunning {
                    Text(L("If the service doesn't run, reinstall MyLittleEnergy or reboot and rejailbreak. It starts with launchd as com.xsxs18.mylittleenergyd."))
                }
            }

            if battery.springBoardSafeMode {
                Section {
                    Button(L("Retry SpringBoard Integration")) {
                        do {
                            let flag = VX.dir + "/springboard-launch"
                            if FileManager.default.fileExists(atPath: flag) {
                                try FileManager.default.removeItem(atPath: flag)
                            }
                            recoveryMessage = L("Retry prepared. Respring manually when ready.")
                        } catch {
                            recoveryMessage = L("Could not prepare retry. Copy the diagnostics report for help.")
                        }
                    }
                    if let recoveryMessage { Text(recoveryMessage).font(.footnote) }
                } footer: {
                    Text(L("Retry only after installing a fix. If initialization fails again, integration stays disabled."))
                }
            }

            Section {
                let state = battery.daemon["state"] as? String ?? "–"
                ValueRow(title: L("Limit State"), value: state)
                ValueRow(title: L("Control Applied"), value: ["none", "inhibit", "bypass"][min(max((battery.daemon["applied"] as? NSNumber)?.intValue ?? 0, 0), 2)])
                ValueRow(title: L("Last Result"), value: String(format: "0x%X", (battery.daemon["lastError"] as? NSNumber)?.intValue ?? 0))
                ValueRow(title: L("Sample Interval"), value: "\((battery.daemon["interval"] as? NSNumber)?.intValue ?? 0) s")
            } header: {
                Text(L("Service"))
            }

            Section {
                Button {
                    testing = true
                    Notify.command(Int(VXCommandSelfTest))
                    DispatchQueue.main.asyncAfter(deadline: .now() + 14) {
                        testing = false
                        battery.loadFiles(throttled: false)
                    }
                } label: {
                    HStack {
                        Label(L("Run Charge Control Test"), systemImage: "stethoscope")
                        Spacer()
                        if testing { ProgressView() }
                    }
                }
                .disabled(testing || !(battery.info?.plugged ?? false))
                if let test = battery.daemon["selfTest"] as? [String: Any] {
                    if !((test["plugged"] as? NSNumber)?.boolValue ?? false) {
                        Text(L("Plug in a charger and run the test again."))
                            .foregroundStyle(.secondary)
                    } else {
                        check(L("Pause charging works"), (test["inhibitWorks"] as? NSNumber)?.boolValue ?? false,
                              detail: controlTestDetail(test, prefix: "inhibit"))
                        check(L("Charger bypass works"), (test["bypassWorks"] as? NSNumber)?.boolValue ?? false,
                              detail: controlTestDetail(test, prefix: "bypass"))
                        if !((test["inhibitWorks"] as? NSNumber)?.boolValue ?? false) ||
                            !((test["bypassWorks"] as? NSNumber)?.boolValue ?? false) {
                            Text(L("A red result means the charging change was not confirmed. The driver code helps diagnose whether this control is supported on your device."))
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text(L("Charge Control Test"))
            } footer: {
                Text(L("Needs a charger. Charging pauses for about 12 seconds while MyLittleEnergy tries both ways of stopping it."))
            }

            Section {
                Button { Notify.command(Int(VXCommandTestAlert)) } label: { Label(L("Test Alert from the Service"), systemImage: "bell") }
                Button { Notify.springBoardTest(Int(VXSBTestAnimation)) } label: { Label(L("Test Charging Animation"), systemImage: "sparkles") }
                Button { Notify.springBoardTest(Int(VXSBTestSound)) } label: { Label(L("Test Sound"), systemImage: "speaker.wave.2") }
            } header: {
                Text(L("SpringBoard"))
            }

            if let actions = battery.springBoard["actions"] as? [String: Any] {
                Section(L("Automation Actions")) {
                    ForEach(actions.keys.sorted(), id: \.self) { key in
                        check(key, (actions[key] as? NSNumber)?.boolValue ?? false, detail: nil)
                    }
                }
            }

            if let log = battery.daemon["log"] as? [String], !log.isEmpty {
                Section(L("Service Log")) {
                    ForEach(Array(log.suffix(25).reversed().enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Button {
                    UIPasteboard.general.string = report()
                    Haptics.success()
                } label: {
                    Label(L("Copy Report"), systemImage: "doc.on.doc")
                }
            } footer: {
                Text(L("Paste the report when you ask for help. It contains no personal data except the battery serial number."))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(L("Diagnostics"))
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            Notify.command(Int(VXCommandWriteStatus))
            Notify.springBoardTest(Int(VXSBTestStatus))
            battery.loadFiles(throttled: false)
        }
    }

    private func controlTestDetail(_ test: [String: Any], prefix: String) -> String {
        let code = (test[prefix + "Result"] as? NSNumber).map {
            String(format: "0x%08X", UInt32(truncatingIfNeeded: $0.int64Value))
        } ?? "–"
        return LF("Driver: %@ · %ld mA", code, (test[prefix + "Amperage"] as? NSNumber)?.intValue ?? 0)
    }

    private func check(_ title: String, _ ok: Bool, detail: String?) -> some View {
        HStack {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(ok ? Color.green : Color.red)
            Text(title)
            Spacer()
            if let detail {
                Text(detail)
                    .foregroundStyle(.secondary)
                    .font(.footnote)
            }
        }
    }

    private func report() -> String {
        var lines = ["MyLittleEnergy \(VX.version) report", "iOS \(UIDevice.current.systemVersion), \(Self.machine())", ""]
        let describe: ([String: Any]) -> String = { dictionary in
            dictionary.keys.sorted().map { "  \($0): \(RawValue.describe(dictionary[$0]))" }.joined(separator: "\n")
        }
        lines.append("[service]")
        lines.append(describe(battery.daemon.filter { $0.key != "log" }))
        lines.append("[springboard]")
        lines.append(describe(battery.springBoard))
        if let actions = battery.springBoard["actions"] as? [String: Any] { lines.append(describe(actions)) }
        if let test = battery.daemon["selfTest"] as? [String: Any] {
            lines.append("[self test]")
            lines.append(describe(test))
        }
        if let info = battery.info {
            lines.append("[battery]")
            lines.append(describe(stringKeyed(info.raw).filter { !($0.value is [String: Any]) && !($0.value is [Any]) }))
        }
        if let log = battery.daemon["log"] as? [String] {
            lines.append("[log]")
            lines.append(contentsOf: log.suffix(40))
        }
        return lines.joined(separator: "\n")
    }

    private static func machine() -> String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { buffer in
            String(decoding: buffer.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
    }
}
