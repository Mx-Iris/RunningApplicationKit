import AppKit
import Darwin

public struct RunningProcess: RunningItem {
    public let pid: pid_t
    public let name: String
    public let executablePath: String?
    public let icon: NSImage?
    public let architecture: Architecture?

    public init(pid: pid_t, name: String, executablePath: String?, icon: NSImage?, architecture: Architecture?) {
        self.pid = pid
        self.name = name
        self.executablePath = executablePath
        self.icon = icon
        self.architecture = architecture
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(pid)
    }

    public static func == (lhs: RunningProcess, rhs: RunningProcess) -> Bool {
        lhs.pid == rhs.pid
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

            // Get process name
            var nameBuffer = [CChar](repeating: 0, count: Int(MAXCOMLEN) + 1)
            let nameLength = proc_name(pid, &nameBuffer, UInt32(nameBuffer.count))
            guard nameLength > 0 else { continue }
            let name = String(cString: nameBuffer)

            // Get executable path
            var pathBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
            let pathLength = proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count))
            let executablePath: String? = pathLength > 0 ? String(cString: pathBuffer) : nil

            // Get icon from executable path
            let icon: NSImage?
            if let executablePath {
                icon = NSWorkspace.shared.icon(forFile: executablePath)
            } else {
                icon = nil
            }

            let process = RunningProcess(
                pid: pid,
                name: name,
                executablePath: executablePath,
                icon: icon,
                architecture: nil  // Architecture detection for arbitrary processes is non-trivial
            )
            processes.append(process)
        }

        return processes.sorted { $0.pid < $1.pid }
    }
}
