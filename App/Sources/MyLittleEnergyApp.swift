import SwiftUI

@main
struct MyLittleEnergyApp: App {
    @StateObject private var settings = SettingsStore.shared
    @StateObject private var battery = BatteryStore.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settings)
                .environmentObject(battery)
                .accentTint()
                .onAppear { registerGroupPath() }
                .onOpenURL(perform: handle)
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                battery.activate()
            } else if phase == .background {
                settings.flush()
                battery.deactivate()
            }
        }
    }

    // The daemon writes the widget data into the app group, but can't always look the path up itself.
    private func registerGroupPath() {
        guard let path = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: VX.groupID)?.path else { return }
        if settings.string("groupPath") != path { settings.set("groupPath", path, immediately: true) }
    }

    // mylittleenergy://full charges to 100% once, mylittleenergy://limit/on and mylittleenergy://limit/off switch the limit.
    private func handle(_ url: URL) {
        switch url.host {
        case "full":
            Notify.command(Int(VXCommandFullOnce))
        case "limit":
            settings.set("limitEnabled", url.lastPathComponent != "off", immediately: true)
        default:
            break
        }
    }
}

struct RootView: View {
    @State private var tab = 0

    var body: some View {
        TabView(selection: $tab) {
            OverviewView(selectTab: { tab = $0 })
                .tabItem { Label(L("Overview"), systemImage: "bolt.batteryblock.fill") }
                .tag(0)
            HistoryView()
                .tabItem { Label(L("History"), systemImage: "chart.xyaxis.line") }
                .tag(1)
            ChargingView()
                .tabItem { Label(L("Charging"), systemImage: "powerplug.fill") }
                .tag(2)
            ModulesView()
                .tabItem { Label(L("Modules"), systemImage: "square.grid.2x2.fill") }
                .tag(3)
        }
    }
}
