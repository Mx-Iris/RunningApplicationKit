import AppKit

public protocol RunningItem: Hashable, Sendable {
    var pid: pid_t { get }
    var name: String { get }
    var icon: NSImage? { get }
    var architecture: Architecture? { get }
}
