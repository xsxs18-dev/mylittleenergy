import SwiftUI

// Trigger and action numbers are shared with the daemon (VXEngine.m) and SpringBoard (VXActions.m).
enum Trigger: Int, CaseIterable, Identifiable {
    case below = 0, above, plugged, unplugged, hot, full
    var id: Int { rawValue }

    var title: String {
        switch self {
        case .below: return L("Battery Drops To")
        case .above: return L("Battery Charges To")
        case .plugged: return L("Charger Connected")
        case .unplugged: return L("Charger Disconnected")
        case .hot: return L("Battery Gets Hot")
        case .full: return L("Fully Charged")
        }
    }

    var symbol: String {
        switch self {
        case .below: return "arrow.down.circle.fill"
        case .above: return "arrow.up.circle.fill"
        case .plugged: return "powerplug.fill"
        case .unplugged: return "powerplug"
        case .hot: return "thermometer.high"
        case .full: return "battery.100"
        }
    }

    var hasLevel: Bool { self == .below || self == .above }
    var hasTemperature: Bool { self == .hot }
}

enum ActionKind: Int, CaseIterable, Identifiable {
    case lowPower = 1, wifi, bluetooth, brightness, darkMode, airplane, location
    var id: Int { rawValue }

    var title: String {
        switch self {
        case .lowPower: return L("Low Power Mode")
        case .wifi: return L("Wi-Fi")
        case .bluetooth: return L("Bluetooth")
        case .brightness: return L("Brightness")
        case .darkMode: return L("Dark Mode")
        case .airplane: return L("Airplane Mode")
        case .location: return L("Location Services")
        }
    }

    var symbol: String {
        switch self {
        case .lowPower: return "battery.25"
        case .wifi: return "wifi"
        case .bluetooth: return "dot.radiowaves.left.and.right"
        case .brightness: return "sun.max.fill"
        case .darkMode: return "moon.fill"
        case .airplane: return "airplane"
        case .location: return "location.fill"
        }
    }

    var color: Color {
        switch self {
        case .lowPower: return .yellow
        case .wifi: return .blue
        case .bluetooth: return .blue
        case .brightness: return .orange
        case .darkMode: return .indigo
        case .airplane: return .orange
        case .location: return .blue
        }
    }

    var isLevel: Bool { self == .brightness }
}

struct RuleAction: Identifiable, Equatable {
    var id = UUID()
    var kind: ActionKind
    var value: Int

    var summary: String {
        if kind.isLevel { return "\(kind.title) \(value)%" }
        return "\(kind.title) \(value != 0 ? L("On") : L("Off"))"
    }
}

struct Rule: Identifiable {
    var id = UUID()
    var name: String
    var enabled: Bool
    var trigger: Trigger
    var value: Double
    var actions: [RuleAction]
    var banner: Bool

    init(name: String = "", trigger: Trigger = .below, value: Double = 20, actions: [RuleAction] = [], banner: Bool = true) {
        self.name = name
        enabled = true
        self.trigger = trigger
        self.value = value
        self.actions = actions
        self.banner = banner
    }

    init(_ dictionary: [String: Any]) {
        name = dictionary["name"] as? String ?? ""
        enabled = (dictionary["enabled"] as? NSNumber)?.boolValue ?? true
        trigger = Trigger(rawValue: (dictionary["trigger"] as? NSNumber)?.intValue ?? 0) ?? .below
        value = (dictionary["value"] as? NSNumber)?.doubleValue ?? 20
        banner = (dictionary["banner"] as? NSNumber)?.boolValue ?? false
        actions = ((dictionary["actions"] as? [Any]) ?? []).compactMap { item in
            guard let action = item as? [String: Any],
                  let kind = ActionKind(rawValue: (action["type"] as? NSNumber)?.intValue ?? 0) else { return nil }
            return RuleAction(kind: kind, value: (action["value"] as? NSNumber)?.intValue ?? 0)
        }
    }

    var dictionary: [String: Any] {
        [
            "name": name,
            // What SpringBoard shows in the banner; follows the trigger while the name is empty.
            "title": displayName,
            "enabled": enabled,
            "trigger": trigger.rawValue,
            "value": value,
            "banner": banner,
            "actions": actions.map { ["type": $0.kind.rawValue, "value": $0.value] },
        ]
    }

    var triggerSummary: String {
        switch trigger {
        case .below: return LF("Battery drops to %ld%%", Int(value))
        case .above: return LF("Battery charges to %ld%%", Int(value))
        case .hot: return LF("Battery reaches %@", Fmt.temperature(value, decimals: 0))
        default: return trigger.title
        }
    }

    var displayName: String {
        name.trimmingCharacters(in: .whitespaces).isEmpty ? triggerSummary : name
    }
}

struct AutomationView: View {
    @EnvironmentObject private var settings: SettingsStore
    @State private var rules: [Rule] = []
    @State private var editing: Rule?

    var body: some View {
        List {
            Section {
                Toggle(isOn: settings.toggle("keepLowPower")) {
                    Label(L("Keep Low Power Mode On"), systemImage: "battery.25")
                }
            } footer: {
                Text(L("iOS turns Low Power Mode off when the battery charges past 80%. MyLittleEnergy turns it back on."))
            }

            Section {
                if rules.isEmpty {
                    Text(L("No rules yet. Start with a preset or create your own."))
                        .foregroundStyle(.secondary)
                }
                ForEach(rules) { rule in
                    HStack(spacing: 12) {
                        IconTile(symbol: rule.trigger.symbol, color: .purple)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(rule.displayName)
                            Text(rule.actions.isEmpty ? L("No actions") : rule.actions.map(\.summary).joined(separator: ", "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Spacer()
                        Toggle("", isOn: elementBinding($rules, rule).enabled)
                            .labelsHidden()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { editing = rule }
                }
                .onDelete { offsets in
                    rules.remove(atOffsets: offsets)
                    save()
                }
                Button {
                    editing = Rule()
                } label: {
                    Label(L("New Rule"), systemImage: "plus.circle.fill")
                }
            } header: {
                Text(L("Rules"))
            }

            Section {
                ForEach(Self.presets.indices, id: \.self) { index in
                    let preset = Self.presets[index]
                    Button {
                        Haptics.success()
                        rules.append(preset)
                        save()
                    } label: {
                        Label(preset.displayName, systemImage: "plus")
                    }
                }
            } header: {
                Text(L("Presets"))
            } footer: {
                Text(L("Rules run in the background while your device is locked too. Banners show only if the rule asks for one."))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(L("Automation"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { rules = settings.dictionaries("rules").map(Rule.init) }
        .onChange(of: rules.map(\.enabled)) { _ in save() }
        .sheet(item: $editing) { rule in
            RuleEditor(rule: rule) { updated in
                if let index = rules.firstIndex(where: { $0.id == updated.id }) {
                    rules[index] = updated
                } else {
                    rules.append(updated)
                }
                save()
            }
            .accentTint()
        }
    }

    private func save() {
        settings.set("rules", rules.map(\.dictionary))
    }

    static var presets: [Rule] {
        [
            Rule(name: L("Low Power Mode at 20%"), trigger: .below, value: 20, actions: [RuleAction(kind: .lowPower, value: 1)]),
            Rule(name: L("Low Power Mode off when charging"), trigger: .plugged, value: 0, actions: [RuleAction(kind: .lowPower, value: 0)], banner: false),
            Rule(name: L("Save energy at 10%"), trigger: .below, value: 10, actions: [RuleAction(kind: .lowPower, value: 1), RuleAction(kind: .brightness, value: 25), RuleAction(kind: .bluetooth, value: 0)]),
            Rule(name: L("Dark Mode below 30%"), trigger: .below, value: 30, actions: [RuleAction(kind: .darkMode, value: 1)]),
            Rule(name: L("Airplane Mode when hot"), trigger: .hot, value: 42, actions: [RuleAction(kind: .airplane, value: 1)]),
        ]
    }
}

private struct RuleEditor: View {
    @State var rule: Rule
    let save: (Rule) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(rule.triggerSummary, text: $rule.name)
                } header: {
                    Text(L("Name"))
                }
                Section {
                    Picker(L("When"), selection: $rule.trigger) {
                        ForEach(Trigger.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                    }
                    if rule.trigger.hasLevel {
                        SliderRow(title: L("Level"), value: $rule.value, range: 1...100, step: 1) { "\(Int($0))%" }
                    }
                    if rule.trigger.hasTemperature {
                        SliderRow(title: L("Temperature"), value: $rule.value, range: 30...50, step: 1) { Fmt.temperature($0, decimals: 0) }
                    }
                } header: {
                    Text(L("Trigger"))
                }
                Section {
                    ForEach(rule.actions) { action in
                        ActionRow(action: elementBinding($rule.actions, action))
                    }
                    .onDelete { rule.actions.remove(atOffsets: $0) }
                    Menu {
                        ForEach(ActionKind.allCases) { kind in
                            Button {
                                rule.actions.append(RuleAction(kind: kind, value: kind.isLevel ? 30 : 1))
                            } label: {
                                Label(kind.title, systemImage: kind.symbol)
                            }
                        }
                    } label: {
                        Label(L("Add Action"), systemImage: "plus.circle.fill")
                    }
                } header: {
                    Text(L("Then"))
                }
                Section {
                    Toggle(L("Show a Banner"), isOn: $rule.banner)
                    Toggle(L("Enabled"), isOn: $rule.enabled)
                }
            }
            .navigationTitle(rule.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: rule.trigger) { trigger in
                if trigger.hasTemperature && rule.value < 30 { rule.value = 40 }
                if trigger.hasLevel && rule.value > 100 { rule.value = 20 }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("Cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Save")) {
                        save(rule)
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct ActionRow: View {
    @Binding var action: RuleAction

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                IconTile(symbol: action.kind.symbol, color: action.kind.color, size: 28)
                Text(action.kind.title)
                Spacer()
                if !action.kind.isLevel {
                    Picker("", selection: $action.value) {
                        Text(L("On")).tag(1)
                        Text(L("Off")).tag(0)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 120)
                }
            }
            if action.kind.isLevel {
                Slider(value: Binding(get: { Double(action.value) }, set: { action.value = Int($0) }), in: 0...100, step: 5)
                Text("\(action.value)%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
