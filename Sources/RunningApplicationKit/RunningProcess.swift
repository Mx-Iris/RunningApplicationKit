import AppKit
import Darwin
import UniformTypeIdentifiers

public struct RunningProcess: RunningItem {
    public let processIdentifier: pid_t
    public let name: String
    public let executablePath: String?
    public let icon: NSImage?
    public let architecture: Architecture?
    public let isSandboxed: Bool

    init(
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

// MARK: - Thread-Safe Cache

private final class ThreadSafeCache<Key: Hashable, Value>: @unchecked Sendable {
    private var storage: [Key: Value] = [:]
    private let lock = NSLock()

    subscript(key: Key) -> Value? {
        get { lock.withLock { storage[key] } }
        set { lock.withLock { storage[key] = newValue } }
    }
}

// MARK: - Process Enumerator

public enum RunningProcessEnumerator {
    // Icon cache keyed by UTType identifier — process icons are just a handful of
    // distinct types (unix executable, generic document, etc.)
    private static let iconCache = ThreadSafeCache<String, NSImage>()
    // Architecture cache keyed by executable path — lookup returns Architecture??
    // where outer nil = cache miss, inner nil = architecture undetectable
    private static let architectureCache = ThreadSafeCache<String, Architecture?>()
    // Sandbox status cache keyed by executable path
    private static let sandboxCache = ThreadSafeCache<String, Bool>()

    /// Build a single `RunningProcess` for the given PID. Returns nil if the process name cannot be determined.
    public static func makeProcess(for pid: pid_t) -> RunningProcess? {
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
        if let executablePath {
            icon = loadCachedIcon(for: executablePath)
        } else {
            icon = nil
        }

        let architecture: Architecture?
        if let executablePath {
            let cached: Architecture?? = architectureCache[executablePath]
            if let cached {
                architecture = cached
            } else {
                let detected = BSDProcess.architecture(for: pid)
                architectureCache[executablePath] = detected
                architecture = detected
            }
        } else {
            architecture = BSDProcess.architecture(for: pid)
        }

        let isSandboxed: Bool
        if let executablePath {
            if let cached = sandboxCache[executablePath] {
                isSandboxed = cached
            } else {
                let detected = BSDProcess.isSandboxed(pid: pid)
                sandboxCache[executablePath] = detected
                isSandboxed = detected
            }
        } else {
            isSandboxed = BSDProcess.isSandboxed(pid: pid)
        }

        return RunningProcess(
            processIdentifier: pid,
            name: name,
            executablePath: executablePath,
            icon: icon,
            architecture: architecture,
            isSandboxed: isSandboxed
        )
    }

    /// Load and cache icon based on the file's UTType. Process executables almost always
    /// map to just two icon types (unix executable or generic document), so caching by
    /// UTType identifier avoids expensive per-file icon lookups entirely.
    static func loadCachedIcon(for path: String) -> NSImage {
        let ext = URL(fileURLWithPath: path).pathExtension
        let uttype: UTType = if ext.isEmpty {
            .unixExecutable
        } else {
            UTType(filenameExtension: ext) ?? .data
        }

        let cacheKey = uttype.identifier
        if let cached = iconCache[cacheKey] {
            return cached
        }
        let icon = NSWorkspace.shared.icon(for: uttype)
        iconCache[cacheKey] = icon
        return icon
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
