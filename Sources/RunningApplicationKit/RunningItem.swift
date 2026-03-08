import AppKit

public protocol RunningItem: Hashable, Sendable {
    var processIdentifier: pid_t { get }
    var name: String { get }
    var localizedName: String? { get }
    var bundleIdentifier: String? { get }
    var bundleURL: URL? { get }
    var executableURL: URL? { get }
    var icon: NSImage? { get }
    var architecture: Architecture? { get }
    var launchDate: Date? { get }
    var isFinishedLaunching: Bool { get }
    var isHidden: Bool { get }
    var isActive: Bool { get }
    var isTerminated: Bool { get }
    var ownsMenuBar: Bool { get }
    var activationPolicy: NSApplication.ActivationPolicy { get }
    var isSandboxed: Bool { get }
}
