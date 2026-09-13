import SwiftUI

@main
struct StayMicApp: App {
    @StateObject private var deviceMonitor = AudioDeviceMonitor()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(deviceMonitor)
        } label: {
            Image(systemName: "mic.fill")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(deviceMonitor)
        }
    }
}
