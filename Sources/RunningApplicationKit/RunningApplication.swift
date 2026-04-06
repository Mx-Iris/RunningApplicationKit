import AppKit

public struct RunningApplication: RunningItem {
    public let processIdentifier: pid_t
    public let name: String
    public let bundleIdentifier: String?
    public let bundleURL: URL?
    public let executableURL: URL?
    public let icon: NSImage?
    public let architecture: Architecture?
    public let launchDate: Date?
    public let isFinishedLaunching: Bool
    public let isHidden: Bool
    public let isActive: Bool
    public let isTerminated: Bool
    public let ownsMenuBar: Bool
    public let activationPolicy: NSApplication.ActivationPolicy
    public internal(set) var isSandboxed: Bool
    public internal(set) var isSandboxResolved: Bool

    public init(from app: NSRunningApplication, resolveSandbox: Bool = true) {
        self.processIdentifier = app.processIdentifier
        self.name = app.localizedName ?? "Unknown"
        self.bundleIdentifier = app.bundleIdentifier
        self.bundleURL = app.bundleURL
        self.executableURL = app.executableURL
        self.icon = app.icon
        self.architecture = app.architecture
        self.launchDate = app.launchDate
        self.isFinishedLaunching = app.isFinishedLaunching
        self.isHidden = app.isHidden
        self.isActive = app.isActive
        self.isTerminated = app.isTerminated
        self.ownsMenuBar = app.ownsMenuBar
        self.activationPolicy = app.activationPolicy
        self.isSandboxed = resolveSandbox ? app.isSandboxed : false
        self.isSandboxResolved = resolveSandbox
    }

    // Hashable: identity by PID
    public func hash(into hasher: inout Hasher) {
        hasher.combine(processIdentifier)
    }

    public static func == (lhs: RunningApplication, rhs: RunningApplication) -> Bool {
        lhs.processIdentifier == rhs.processIdentifier
    }
}

// MARK: - ObjC Bridge Class

@objc(RAKRunningApplication)
public final class RAKRunningApplication: NSObject {
    @objc public let processIdentifier: pid_t
    @objc public let name: String
    @objc public let bundleIdentifier: String?
    @objc public let bundleURL: URL?
    @objc public let executableURL: URL?
    @objc public let icon: NSImage?
    public let architecture: Architecture?
    @objc public let launchDate: Date?
    @objc public let isFinishedLaunching: Bool
    @objc public let isHidden: Bool
    @objc public let isActive: Bool
    @objc public let isTerminated: Bool
    @objc public let ownsMenuBar: Bool
    @objc public let activationPolicy: NSApplication.ActivationPolicy
    @objc public let isSandboxed: Bool
    @objc public let isSandboxResolved: Bool

    init(_ source: RunningApplication) {
        self.processIdentifier = source.processIdentifier
        self.name = source.name
        self.bundleIdentifier = source.bundleIdentifier
        self.bundleURL = source.bundleURL
        self.executableURL = source.executableURL
        self.icon = source.icon
        self.architecture = source.architecture
        self.launchDate = source.launchDate
        self.isFinishedLaunching = source.isFinishedLaunching
        self.isHidden = source.isHidden
        self.isActive = source.isActive
        self.isTerminated = source.isTerminated
        self.ownsMenuBar = source.ownsMenuBar
        self.activationPolicy = source.activationPolicy
        self.isSandboxed = source.isSandboxed
        self.isSandboxResolved = source.isSandboxResolved
        super.init()
    }
}

// MARK: - _ObjectiveCBridgeable

extension RunningApplication: _ObjectiveCBridgeable {
    public typealias _ObjectiveCType = RAKRunningApplication

    public func _bridgeToObjectiveC() -> RAKRunningApplication {
        RAKRunningApplication(self)
    }

    public static func _forceBridgeFromObjectiveC(_ source: RAKRunningApplication, result: inout RunningApplication?) {
        result = _makeRunningApplication(from: source)
    }

    public static func _conditionallyBridgeFromObjectiveC(_ source: RAKRunningApplication, result: inout RunningApplication?) -> Bool {
        result = _makeRunningApplication(from: source)
        return true
    }

    public static func _unconditionallyBridgeFromObjectiveC(_ source: RAKRunningApplication?) -> RunningApplication {
        guard let source else { fatalError("Cannot bridge nil RAKRunningApplication") }
        return _makeRunningApplication(from: source)
    }

    private static func _makeRunningApplication(from source: RAKRunningApplication) -> RunningApplication {
        var application = RunningApplication(
            processIdentifier: source.processIdentifier,
            name: source.name,
            bundleIdentifier: source.bundleIdentifier,
            bundleURL: source.bundleURL,
            executableURL: source.executableURL,
            icon: source.icon,
            architecture: source.architecture,
            launchDate: source.launchDate,
            isFinishedLaunching: source.isFinishedLaunching,
            isHidden: source.isHidden,
            isActive: source.isActive,
            isTerminated: source.isTerminated,
            ownsMenuBar: source.ownsMenuBar,
            activationPolicy: source.activationPolicy,
            isSandboxed: source.isSandboxed,
            isSandboxResolved: source.isSandboxResolved
        )
        return application
    }

    private init(
        processIdentifier: pid_t,
        name: String,
        bundleIdentifier: String?,
        bundleURL: URL?,
        executableURL: URL?,
        icon: NSImage?,
        architecture: Architecture?,
        launchDate: Date?,
        isFinishedLaunching: Bool,
        isHidden: Bool,
        isActive: Bool,
        isTerminated: Bool,
        ownsMenuBar: Bool,
        activationPolicy: NSApplication.ActivationPolicy,
        isSandboxed: Bool,
        isSandboxResolved: Bool
    ) {
        self.processIdentifier = processIdentifier
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.bundleURL = bundleURL
        self.executableURL = executableURL
        self.icon = icon
        self.architecture = architecture
        self.launchDate = launchDate
        self.isFinishedLaunching = isFinishedLaunching
        self.isHidden = isHidden
        self.isActive = isActive
        self.isTerminated = isTerminated
        self.ownsMenuBar = ownsMenuBar
        self.activationPolicy = activationPolicy
        self.isSandboxed = isSandboxed
        self.isSandboxResolved = isSandboxResolved
    }
}
