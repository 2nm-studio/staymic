import SwiftUI

struct MicrophoneRow: View {
    @EnvironmentObject private var deviceMonitor: AudioDeviceMonitor
    let device: AudioInputDevice

    @State private var isHovering = false

    private var volumeBinding: Binding<Double> {
        Binding(
            get: { Double(device.volume ?? 0) },
            set: { deviceMonitor.userDidChangeVolume(uid: device.uid, value: Float($0)) }
        )
    }

    private var volumeLockBinding: Binding<Bool> {
        Binding(
            get: { device.volumeLockEnabled },
            set: { deviceMonitor.setVolumeLockEnabled($0, uid: device.uid) }
        )
    }

    private var defaultLockBinding: Binding<Bool> {
        Binding(
            get: { device.isDefaultLockEnabled },
            set: { deviceMonitor.setDefaultLockEnabled($0, uid: device.uid) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if device.isConnected {
                if device.supportsVolumeControl {
                    volumeSlider
                } else {
                    Label("Volume control not available", systemImage: "slider.horizontal.3")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                controls
            } else {
                Label("Locked • Disconnected • Waiting for device", systemImage: "cable.connector.slash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isHovering ? Color.primary.opacity(0.06) : .clear)
        )
        .onHover { isHovering = $0 }
        .opacity(device.isConnected ? 1 : 0.6)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: device.isDefaultInput ? "mic.fill" : "mic")
                .foregroundStyle(device.isDefaultInput ? Color.accentColor : .secondary)
                .frame(width: 16)

            Text(device.name)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)

            Spacer()

            if let percent = device.volumePercent, device.isConnected {
                Text("\(percent)%")
                    .font(.system(size: 12, weight: .regular).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard device.isConnected, !device.isDefaultInput else { return }
            deviceMonitor.userDidSelectDefaultDevice(uid: device.uid)
        }
    }

    private var volumeSlider: some View {
        Slider(value: volumeBinding, in: 0...1)
            .controlSize(.small)
    }

    private var controls: some View {
        HStack(spacing: 16) {
            if device.supportsVolumeControl {
                Toggle(isOn: volumeLockBinding) {
                    Label("Lock Volume", systemImage: device.volumeLockEnabled ? "lock.fill" : "lock.open")
                }
                .toggleStyle(.checkbox)
                .font(.caption)
            }

            Toggle(isOn: defaultLockBinding) {
                Label("Keep as Microphone", systemImage: device.isDefaultLockEnabled ? "lock.fill" : "lock.open")
            }
            .toggleStyle(.checkbox)
            .font(.caption)

            Spacer()
        }
    }
}
