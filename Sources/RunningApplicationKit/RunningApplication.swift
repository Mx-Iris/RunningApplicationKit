import AppKit

public struct RunningApplication: RunningItem {
    public let pid: pid_t
    public let name: String
    public let bundleIdentifier: String?
    public let icon: NSImage?
    public let architecture: Architecture?
    public let isSandboxed: Bool

    public init(from app: NSRunningApplication) {
        self.pid = app.processIdentifier
        self.name = app.localizedName ?? "Unknown"
        self.bundleIdentifier = app.bundleIdentifier
        self.icon = app.icon
        self.architecture = app.architecture
        self.isSandboxed = app.isSandboxed
    }

    // Hashable: identity by PID
    public func hash(into hasher: inout Hasher) {
        hasher.combine(pid)
    }

    public static func == (lhs: RunningApplication, rhs: RunningApplication) -> Bool {
        lhs.pid == rhs.pid
    }
}
