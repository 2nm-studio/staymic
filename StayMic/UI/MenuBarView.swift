import AppKit
import SwiftUI

/// The content shown when the StayMic status-bar icon is clicked.
///
/// This is a `.window`-style `MenuBarExtra`, not a plain `NSMenu` — that's
/// what lets it host real sliders and checkboxes instead of static menu
/// items.
struct MenuBarView: View {
    @EnvironmentObject private var deviceMonitor: AudioDeviceMonitor
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            deviceList
            Divider()
            footer
        }
        .frame(width: 320)
    }

    private var header: some View {
        HStack {
            Text("StayMic")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var deviceList: some View {
        if deviceMonitor.devices.isEmpty {
            Text("No microphones found")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(20)
        } else {
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(deviceMonitor.devices) { device in
                        MicrophoneRow(device: device)
                    }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 4)
            }
            .frame(maxHeight: 380)
        }
    }

    private var footer: some View {
        VStack(spacing: 2) {
            FooterButton(title: "Settings…", systemImage: "gearshape") {
                openSettings()
                NSApp.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut(",", modifiers: .command)

            FooterButton(title: "Quit StayMic", systemImage: "power") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .padding(.vertical, 6)
    }
}

private struct FooterButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 12.5))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isHovering ? Color.primary.opacity(0.08) : .clear)
                )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .onHover { isHovering = $0 }
    }
}
