import AppKit
import Darwin

public struct RunningProcess: RunningItem {
    public let processIdentifier: pid_t
    public let name: String
    public let localizedName: String?
    public let bundleIdentifier: String?
    public let bundleURL: URL?
    public let executableURL: URL?
    public let executablePath: String?
    public let icon: NSImage?
    public let architecture: Architecture?
    public let launchDate: Date?
    public let isFinishedLaunching: Bool
    public let isHidden: Bool
    public let isActive: Bool
    public let isTerminated: Bool
    public let ownsMenuBar: Bool
    public let activationPolicy: NSApplication.ActivationPolicy
    public let isSandboxed: Bool

    public init(
        processIdentifier: pid_t,
        name: String,
        localizedName: String? = nil,
        bundleIdentifier: String? = nil,
        bundleURL: URL? = nil,
        executableURL: URL? = nil,
        executablePath: String? = nil,
        icon: NSImage? = nil,
        architecture: Architecture? = nil,
        launchDate: Date? = nil,
        isFinishedLaunching: Bool = false,
        isHidden: Bool = false,
        isActive: Bool = false,
        isTerminated: Bool = false,
        ownsMenuBar: Bool = false,
        activationPolicy: NSApplication.ActivationPolicy = .prohibited,
        isSandboxed: Bool = false
    ) {
        self.processIdentifier = processIdentifier
        self.name = name
        self.localizedName = localizedName
        self.bundleIdentifier = bundleIdentifier
        self.bundleURL = bundleURL
        self.executableURL = executableURL
        self.executablePath = executablePath
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
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(processIdentifier)
    }

    public static func == (lhs: RunningProcess, rhs: RunningProcess) -> Bool {
        lhs.processIdentifier == rhs.processIdentifier
    }
}

public enum RunningProcessEnumerator {
    /// List all running processes, excluding those that are NSRunningApplications.
    public static func listProcesses(excludingApplications: Bool = true) -> [RunningProcess] {
        let appPIDs: Set<pid_t>
        if excludingApplications {
            appPIDs = Set(NSWorkspace.shared.runningApplications.map(\.processIdentifier))
        } else {
            appPIDs = []
        }

        let bufferSize = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard bufferSize > 0 else { return [] }

        let pidCount = Int(bufferSize) / MemoryLayout<pid_t>.size
        var pids = [pid_t](repeating: 0, count: pidCount)
        let actualSize = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, bufferSize)
        guard actualSize > 0 else { return [] }

        let actualCount = Int(actualSize) / MemoryLayout<pid_t>.size
        var processes: [RunningProcess] = []

        for i in 0..<actualCount {
            let pid = pids[i]
            guard pid > 0, !appPIDs.contains(pid) else { continue }

            // Get executable path (try this first as it's more reliable)
            var pathBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
            let pathLength = proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count))
            let executablePath: String? = pathLength > 0 ? String(cString: pathBuffer) : nil

            // Get process name, fallback to path basename
            var nameBuffer = [CChar](repeating: 0, count: Int(MAXCOMLEN) + 1)
            let nameLength = proc_name(pid, &nameBuffer, UInt32(nameBuffer.count))
            let name: String
            if nameLength > 0 {
                name = String(cString: nameBuffer)
            } else if let executablePath {
                name = (executablePath as NSString).lastPathComponent
            } else {
                continue
            }

            // Get icon from executable path
            let icon: NSImage?
            if let executablePath {
                icon = NSWorkspace.shared.icon(forFile: executablePath)
            } else {
                icon = nil
            }

            let process = RunningProcess(
                processIdentifier: pid,
                name: name,
                executablePath: executablePath,
                icon: icon,
                architecture: nil  // Architecture detection for arbitrary processes is non-trivial
            )
            processes.append(process)
        }

        return processes.sorted { $0.processIdentifier < $1.processIdentifier }
    }
}
