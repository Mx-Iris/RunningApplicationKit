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
        let target = await self.target

        switch target {
        case .pid(let targetPID):
            // Direct check via kill(pid, 0) avoids enumerating all processes
            return ProcessInfo.isRunning(pid: targetPID) ? [targetPID] : []

        case .name(let targetName):
            var matchingPIDs: Set<pid_t> = []
            for pid in ProcessInfo.allPIDs() {
                if ProcessInfo.name(for: pid) == targetName {
                    matchingPIDs.insert(pid)
                }
            }
            return matchingPIDs

        case .executablePath(let targetPath):
            var matchingPIDs: Set<pid_t> = []
            for pid in ProcessInfo.allPIDs() {
                if ProcessInfo.executablePath(for: pid) == targetPath {
                    matchingPIDs.insert(pid)
                }
            }
            return matchingPIDs
        }
    }
}
