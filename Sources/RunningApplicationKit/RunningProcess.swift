import AppKit
import Darwin

public struct RunningProcess: RunningItem {
    public let processIdentifier: pid_t
    public let name: String
    public let executablePath: String?
    public let icon: NSImage?
    public let architecture: Architecture?
    public let isSandboxed: Bool

    public init(
        processIdentifier: pid_t,
        name: String,
        executablePath: String? = nil,
        icon: NSImage? = nil,
        architecture: Architecture? = nil,
        isSandboxed: Bool = false
    ) {
        self.processIdentifier = processIdentifier
        self.name = name
        self.executablePath = executablePath
        self.icon = icon
        self.architecture = architecture
        self.isSandboxed = isSandboxed
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(processIdentifier)
    }

    public static func == (lhs: RunningProcess, rhs: RunningProcess) -> Bool {
        lhs.processIdentifier == rhs.processIdentifier
    }
}

public enum RunningProcessEnumerator {
    // Caches keyed by executable path — icon and architecture don't change for a given binary
    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var iconCache: [String: NSImage] = [:]
    nonisolated(unsafe) private static var architectureCache: [String: Architecture?] = [:]

    /// Build a single `RunningProcess` for the given PID. Returns nil if the process name cannot be determined.
    /// When `loadIcon` is false, the icon field is nil — use `loadCachedIcon(for:)` separately to load it later.
    public static func makeProcess(for pid: pid_t, loadIcon: Bool = true) -> RunningProcess? {
        let executablePath = BSDProcess.executablePath(for: pid)

        let name: String
        if let procName = BSDProcess.name(for: pid) {
            name = procName
        } else if let executablePath {
            name = (executablePath as NSString).lastPathComponent
        } else {
            return nil
        }

        let icon: NSImage?
        if loadIcon, let executablePath {
            icon = loadCachedIcon(for: executablePath)
        } else {
            icon = nil
        }

        let architecture: Architecture?
        if let executablePath {
            // Check cache under lock, load outside lock to avoid holding it during I/O
            let cached: Architecture?? = cacheLock.withLock { architectureCache[executablePath] }
            if let cached {
                architecture = cached
            } else {
                let detected = BSDProcess.architecture(for: pid)
                cacheLock.withLock { architectureCache[executablePath] = detected }
                architecture = detected
            }
        } else {
            architecture = BSDProcess.architecture(for: pid)
        }

        return RunningProcess(
            processIdentifier: pid,
            name: name,
            executablePath: executablePath,
            icon: icon,
            architecture: architecture,
            isSandboxed: BSDProcess.isSandboxed(pid: pid)
        )
    }

    /// Load and cache icon for the given executable path. Thread-safe; does not hold
    /// the lock during the (potentially slow) `NSWorkspace.shared.icon(forFile:)` call.
    static func loadCachedIcon(for path: String) -> NSImage {
        if let cached = cacheLock.withLock({ iconCache[path] }) {
            return cached
        }
        let loaded = NSWorkspace.shared.icon(forFile: path)
        cacheLock.withLock { iconCache[path] = loaded }
        return loaded
    }

    /// List all running processes, excluding those that are NSRunningApplications.
    public static func listProcesses(excludingApplications: Bool = true) -> [RunningProcess] {
        let appPIDs: Set<pid_t>
        if excludingApplications {
            appPIDs = Set(NSWorkspace.shared.runningApplications.map(\.processIdentifier))
        } else {
            appPIDs = []
        }

        return BSDProcess.allPIDs()
            .filter { !appPIDs.contains($0) }
            .compactMap { makeProcess(for: $0) }
            .sorted { $0.processIdentifier < $1.processIdentifier }
    }
}
