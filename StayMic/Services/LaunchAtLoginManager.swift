import Foundation
import ServiceManagement

/// Wraps `SMAppService.mainApp`, the modern (non-deprecated) login-item API.
enum LaunchAtLoginManager {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                guard SMAppService.mainApp.status != .enabled else { return }
                try SMAppService.mainApp.register()
                Log.app.notice("Launch at Login enabled")
            } else {
                guard SMAppService.mainApp.status == .enabled else { return }
                try SMAppService.mainApp.unregister()
                Log.app.notice("Launch at Login disabled")
            }
        } catch {
            Log.app.error("Failed to update Launch at Login: \(error.localizedDescription, privacy: .public)")
        }
    }
}
