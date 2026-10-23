import SwiftUI

struct LevelAlert: Identifiable {
    var id = UUID()
    var level: Int
    var up: Bool
    var enabled: Bool

    init(level: Int, up: Bool, enabled: Bool) {
        self.level = level
        self.up = up
        self.enabled = enabled
    }

    init(_ dictionary: [String: Any]) {
        level = (dictionary["level"] as? NSNumber)?.intValue ?? 20
        up = (dictionary["up"] as? NSNumber)?.boolValue ?? false
        enabled = (dictionary["enabled"] as? NSNumber)?.boolValue ?? true
    }

    var dictionary: [String: Any] { ["level": level, "up": up, "enabled": enabled] }
}

struct AlertsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @State private var alerts: [LevelAlert] = []
    @State private var adding = false

    var body: some View {
        List {
            Section {
                Toggle(isOn: settings.toggle("alertsEnabled")) {
                    Label(L("Alerts"), systemImage: "bell.badge.fill")
                }
            }
            if settings.bool("alertsEnabled") {
                Section {
                    ForEach(alerts) { alert in
                        Toggle(isOn: elementBinding($alerts, alert).enabled) {
                            Label(alert.up ? LF("Charged to %ld%%", alert.level) : LF("Drops to %ld%%", alert.level),
                                  systemImage: alert.up ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                        }
                    }
                    .onDelete { offsets in
                        alerts.remove(atOffsets: offsets)
                        saveAlerts()
                    }
                    Button {
                        adding = true
                    } label: {
                        Label(L("Add Level Alert"), systemImage: "plus.circle.fill")
                    }
                } header: {
                    Text(L("Battery Level"))
                }
                Section {
                    Toggle(L("Fully Charged"), isOn: settings.toggle("alertFull"))
                    Toggle(L("Charge Limit Reached"), isOn: settings.toggle("alertLimit"))
                    Toggle(L("Battery Hot"), isOn: settings.toggle("alertHot"))
                    if settings.bool("alertHot") {
                        SliderRow(title: L("Hot Above"), value: settings.rounded("alertHotTemp"), range: 32...50, step: 1) { Fmt.temperature($0, decimals: 0) }
                    }
                } header: {
                    Text(L("Events"))
                }
                Section {
                    Toggle(L("Banner"), isOn: settings.toggle("alertBanner"))
                    NavigationLink {
                        SoundPicker(key: "alertSound")
                    } label: {
                        ValueRow(title: L("Sound"), value: Sounds.displayName(settings.string("alertSound")))
                    }
                    Toggle(L("Speak Alerts"), isOn: settings.toggle("alertSpeech"))
                    Button {
                        settings.flush()
                        Notify.springBoardTest(Int(VXSBTestBanner))
                    } label: {
                        Label(L("Test Alert"), systemImage: "play.fill")
                    }
                } header: {
                    Text(L("Presentation"))
                }
            }
            Section {
                Toggle(L("Sound When Plugged In"), isOn: settings.toggle("plugSoundEnabled"))
                if settings.bool("plugSoundEnabled") {
                    NavigationLink { SoundPicker(key: "plugSound") } label: {
                        ValueRow(title: L("Plug-in Sound"), value: Sounds.displayName(settings.string("plugSound")))
                    }
                }
                Toggle(L("Sound When Unplugged"), isOn: settings.toggle("unplugSoundEnabled"))
                if settings.bool("unplugSoundEnabled") {
                    NavigationLink { SoundPicker(key: "unplugSound") } label: {
                        ValueRow(title: L("Unplug Sound"), value: Sounds.displayName(settings.string("unplugSound")))
                    }
                }
            } header: {
                Text(L("Charger Sounds"))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(L("Alerts & Sounds"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { alerts = settings.dictionaries("alertLevels").map(LevelAlert.init) }
        .onChange(of: alerts.map(\.enabled)) { _ in saveAlerts() }
        .sheet(isPresented: $adding) {
            AddLevelAlertView { alert in
                alerts.append(alert)
                alerts.sort { $0.level < $1.level }
                saveAlerts()
            }
            .presentationDetents([.medium])
            .accentTint()
        }
    }

    private func saveAlerts() {
        settings.set("alertLevels", alerts.map(\.dictionary))
    }
}

private struct AddLevelAlertView: View {
    let add: (LevelAlert) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var level = 30.0
    @State private var up = false

    var body: some View {
        NavigationStack {
            Form {
                Picker(L("When the Battery"), selection: $up) {
                    Text(L("Drops To")).tag(false)
                    Text(L("Charges To")).tag(true)
                }
                .pickerStyle(.segmented)
                SliderRow(title: L("Level"), value: $level, range: 5...100, step: 5) { "\(Int($0))%" }
            }
            .navigationTitle(L("Level Alert"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("Cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Add")) {
                        add(LevelAlert(level: Int(level), up: up, enabled: true))
                        dismiss()
                    }
                }
            }
        }
    }
}

struct SoundPicker: View {
    let key: String
    @EnvironmentObject private var settings: SettingsStore
    @State private var sounds: [String] = []
    @State private var search = ""

    var body: some View {
        List {
            soundRow("")
            ForEach(filtered, id: \.self) { soundRow($0) }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $search)
        .navigationTitle(L("Sound"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if sounds.isEmpty { sounds = Sounds.all() } }
    }

    private var filtered: [String] {
        search.isEmpty ? sounds : sounds.filter { Sounds.displayName($0).localizedCaseInsensitiveContains(search) }
    }

    private func soundRow(_ sound: String) -> some View {
        Button {
            settings.set(key, sound)
            Sounds.play(sound)
        } label: {
            HStack {
                Text(Sounds.displayName(sound))
                    .foregroundStyle(.primary)
                Spacer()
                if settings.string(key) == sound {
                    Image(systemName: "checkmark")
                        .foregroundStyle(settings.accent)
                        .font(.body.weight(.semibold))
                }
            }
        }
    }
}
