import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gearshape") }

            BehaviorSettingsTab()
                .tabItem { Label("Behavior", systemImage: "arrow.triangle.2.circlepath") }

            DevicesSettingsTab()
                .tabItem { Label("Devices", systemImage: "mic") }
        }
        .frame(width: 460)
        .scenePadding()
    }
}

private struct GeneralSettingsTab: View {
    @State private var launchAtLogin = LaunchAtLoginManager.isEnabled

    var body: some View {
        Form {
            Toggle("Launch StayMic at Login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, newValue in
                    LaunchAtLoginManager.setEnabled(newValue)
                }

            Section {
                Text("StayMic lives in the menu bar. It never records or transmits audio — it only reads and writes CoreAudio device settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 12)
    }
}

private struct BehaviorSettingsTab: View {
    @ObservedObject private var preferences = PreferencesStore.shared

    var body: some View {
        Form {
            Section("On reconnect") {
                Toggle("Restore locked input volume", isOn: $preferences.restoreVolumeAfterReconnect)
                Toggle("Restore locked microphone as default", isOn: $preferences.restoreDefaultAfterReconnect)
            }

            Section {
                Text("When a locked microphone disconnects, StayMic remembers it and waits. These settings control what happens automatically once it comes back.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 12)
    }
}

private struct DevicesSettingsTab: View {
    @EnvironmentObject private var deviceMonitor: AudioDeviceMonitor
    @ObservedObject private var preferences = PreferencesStore.shared

    var body: some View {
        Form {
            if preferences.deviceStates.isEmpty && preferences.lockedDefaultDeviceUID == nil {
                Text("No remembered devices yet. Lock a microphone's volume or set it as your locked default to see it here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(rememberedUIDs, id: \.self) { uid in
                    DeviceSettingsRow(uid: uid)
                }
            }
        }
        .padding(.top, 12)
        .environmentObject(deviceMonitor)
    }

    private var rememberedUIDs: [String] {
        var uids = Set(preferences.deviceStates.keys)
        if let locked = preferences.lockedDefaultDeviceUID {
            uids.insert(locked)
        }
        return uids.sorted()
    }
}

private struct DeviceSettingsRow: View {
    @EnvironmentObject private var deviceMonitor: AudioDeviceMonitor
    @ObservedObject private var preferences = PreferencesStore.shared
    let uid: String

    private var displayName: String {
        deviceMonitor.devices.first(where: { $0.uid == uid })?.name
            ?? preferences.state(for: uid).lastKnownName
            ?? preferences.lockedDefaultDeviceName
            ?? uid
    }

    private var isConnected: Bool {
        deviceMonitor.devices.first(where: { $0.uid == uid })?.isConnected ?? false
    }

    private var hasAnyLock: Bool {
        preferences.state(for: uid).volumeLockEnabled || preferences.lockedDefaultDeviceUID == uid
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(.system(size: 13, weight: .medium))
                Text(statusLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if hasAnyLock {
                Button("Forget") {
                    deviceMonitor.forgetDevice(uid: uid)
                }
                .buttonStyle(.link)
                .font(.caption)
                .help("Clear all locks StayMic remembers for this device.")
            }
            Circle()
                .fill(isConnected ? Color.green : Color.secondary.opacity(0.4))
                .frame(width: 8, height: 8)
        }
        .padding(.vertical, 4)
    }

    private var statusLine: String {
        var parts: [String] = []
        let state = preferences.state(for: uid)
        if state.volumeLockEnabled, let volume = state.lockedVolume {
            parts.append("Volume locked at \(Int((volume * 100).rounded()))%")
        }
        if preferences.lockedDefaultDeviceUID == uid {
            parts.append("Locked as default microphone")
        }
        if !isConnected {
            parts.append("Disconnected")
        }
        return parts.isEmpty ? "No locks" : parts.joined(separator: " • ")
    }
}
