import OSLog

/// Centralized `Logger` categories for StayMic.
///
/// Kept intentionally small: one category per subsystem area so log output
/// stays easy to filter in Console.app while debugging CoreAudio event flow.
enum Log {
    private static let subsystem = "studio.2nm.StayMic"

    static let audio = Logger(subsystem: subsystem, category: "audio")
    static let volumeLock = Logger(subsystem: subsystem, category: "volume-lock")
    static let deviceLock = Logger(subsystem: subsystem, category: "device-lock")
    static let preferences = Logger(subsystem: subsystem, category: "preferences")
    static let app = Logger(subsystem: subsystem, category: "app")
}
