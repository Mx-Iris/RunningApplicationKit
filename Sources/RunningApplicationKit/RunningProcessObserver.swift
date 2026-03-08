import AppKit
import Darwin

public actor RunningProcessObserver {
    public enum Target: Sendable {
        case pid(pid_t)
        case name(String)
        case executablePath(String)
    }

    public let target: Target
    public let pollingInterval: TimeInterval

    private var pollingTask: Task<Void, Never>?
    private var knownPIDs: Set<pid_t> = []
    private var didLaunch: @Sendable () -> Void = {}
    private var didTerminate: @Sendable () -> Void = {}

    public init(target: Target, pollingInterval: TimeInterval = 2.0) {
        self.target = target
        self.pollingInterval = pollingInterval
    }

    public func onLaunch(_ handler: @escaping @Sendable () -> Void) {
        self.didLaunch = handler
    }

    public func onTerminate(_ handler: @escaping @Sendable () -> Void) {
        self.didTerminate = handler
    }

    public func start() {
        pollingTask = Task { [weak self] in
            guard let self else { return }
            // Initial scan
            let initialPIDs = await self.findMatchingPIDs()
            await self.updateKnownPIDs(initialPIDs)

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(pollingInterval * 1_000_000_000))
                guard !Task.isCancelled else { break }
                let currentPIDs = await self.findMatchingPIDs()
                await self.diffAndNotify(currentPIDs)
            }
        }
    }

    public func stop() {
        pollingTask?.cancel()
        pollingTask = nil
        knownPIDs = []
    }

    private func updateKnownPIDs(_ pids: Set<pid_t>) {
        knownPIDs = pids
    }

    private func diffAndNotify(_ currentPIDs: Set<pid_t>) {
        let launched = currentPIDs.subtracting(knownPIDs)
        let terminated = knownPIDs.subtracting(currentPIDs)

        if !launched.isEmpty {
            didLaunch()
        }
        if !terminated.isEmpty {
            didTerminate()
        }

        knownPIDs = currentPIDs
    }

    private nonisolated func findMatchingPIDs() async -> Set<pid_t> {
        let bufferSize = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard bufferSize > 0 else { return [] }

        let pidCount = Int(bufferSize) / MemoryLayout<pid_t>.size
        var pids = [pid_t](repeating: 0, count: pidCount)
        let actualSize = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, bufferSize)
        guard actualSize > 0 else { return [] }

        let actualCount = Int(actualSize) / MemoryLayout<pid_t>.size
        var matchingPIDs: Set<pid_t> = []

        let target = await self.target

        for i in 0..<actualCount {
            let pid = pids[i]
            guard pid > 0 else { continue }

            switch target {
            case .pid(let targetPID):
                if pid == targetPID {
                    matchingPIDs.insert(pid)
                }
            case .name(let targetName):
                var nameBuffer = [CChar](repeating: 0, count: Int(MAXCOMLEN) + 1)
                let nameLength = proc_name(pid, &nameBuffer, UInt32(nameBuffer.count))
                if nameLength > 0 {
                    let name = String(cString: nameBuffer)
                    if name == targetName {
                        matchingPIDs.insert(pid)
                    }
                }
            case .executablePath(let targetPath):
                var pathBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
                let pathLength = proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count))
                if pathLength > 0 {
                    let path = String(cString: pathBuffer)
                    if path == targetPath {
                        matchingPIDs.insert(pid)
                    }
                }
            }
        }

        return matchingPIDs
    }
}
