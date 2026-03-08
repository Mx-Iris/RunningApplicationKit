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
    private static var iconCache: [String: NSImage] = [:]
    private static var architectureCache: [String: Architecture?] = [:]

    /// List all running processes, excluding those that are NSRunningApplications.
    public static func listProcesses(excludingApplications: Bool = true) -> [RunningProcess] {
        let appPIDs: Set<pid_t>
        if excludingApplications {
            appPIDs = Set(NSWorkspace.shared.runningApplications.map(\.processIdentifier))
        } else {
            appPIDs = []
        }

        var processes: [RunningProcess] = []

        for pid in ProcessInfo.allPIDs() {
            guard !appPIDs.contains(pid) else { continue }

            let executablePath = ProcessInfo.executablePath(for: pid)

            // Get process name, fallback to path basename
            let name: String
            if let procName = ProcessInfo.name(for: pid) {
                name = procName
            } else if let executablePath {
                name = (executablePath as NSString).lastPathComponent
            } else {
                continue
            }

            let icon: NSImage?
            if let executablePath {
                if let cached = iconCache[executablePath] {
                    icon = cached
                } else {
                    let loaded = NSWorkspace.shared.icon(forFile: executablePath)
                    iconCache[executablePath] = loaded
                    icon = loaded
                }
            } else {
                icon = nil
            }

            let architecture: Architecture?
            if let executablePath {
                if let cached = architectureCache[executablePath] {
                    architecture = cached
                } else {
                    let detected = ProcessInfo.architecture(for: pid)
                    architectureCache[executablePath] = detected
                    architecture = detected
                }
            } else {
                architecture = ProcessInfo.architecture(for: pid)
            }

            let process = RunningProcess(
                processIdentifier: pid,
                name: name,
                executablePath: executablePath,
                icon: icon,
                architecture: architecture,
                isSandboxed: ProcessInfo.isSandboxed(pid: pid)
            )
            processes.append(process)
        }

        return processes.sorted { $0.processIdentifier < $1.processIdentifier }
    }
}
