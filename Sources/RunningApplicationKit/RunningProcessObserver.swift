import AppKit
import Darwin
internal import ProcessInformation

public actor RunningProcessObserver {
    public enum Target: Sendable {
        case pid(pid_t)
        /// Matches a process whose kernel name or executable file name is this
        /// name. The two differ when the file name is longer than the 31 bytes
        /// the kernel reports, and only the kernel name is known for a process
        /// whose path the kernel does not give out.
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
        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            guard let self else { return }
            // Initial scan
            let initialPIDs = self.findMatchingPIDs()
            await self.updateKnownPIDs(initialPIDs)

            while !Task.isCancelled {
                // While a watched process identifier runs, the kernel reports its
                // exit as it happens; polling would notice it up to an interval late.
                if case .pid(let targetPID) = self.target,
                   await self.isKnown(targetPID),
                   await Self.waitForTermination(of: targetPID) {
                    await self.diffAndNotify([])
                    continue
                }
                try? await Task.sleep(nanoseconds: UInt64(pollingInterval * 1_000_000_000))
                guard !Task.isCancelled else { break }
                let currentPIDs = self.findMatchingPIDs()
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

    private func isKnown(_ pid: pid_t) -> Bool {
        knownPIDs.contains(pid)
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

    /// Waits until the process exits, through the kernel's exit notification.
    ///
    /// - Returns: `true` once the process has exited. `false` before macOS 15,
    ///   or when the wait could not be set up or was cancelled; the caller then
    ///   polls instead.
    private static func waitForTermination(of pid: pid_t) async -> Bool {
        guard #available(macOS 15, *) else { return false }
        do {
            try await ProcessIdentifier(rawValue: pid).waitForTermination()
            return true
        } catch {
            return false
        }
    }

    private nonisolated func findMatchingPIDs() -> Set<pid_t> {
        switch target {
        case .pid(let targetPID):
            return BSDProcess.isRunning(pid: targetPID) ? [targetPID] : []
        case .name(let targetName):
            return Set(BSDProcess.allPIDs().filter { Self.process($0, isNamed: targetName) })
        case .executablePath(let targetPath):
            return Set(BSDProcess.allPIDs().filter { BSDProcess.executablePath(for: $0) == targetPath })
        }
    }

    private static func process(_ pid: pid_t, isNamed name: String) -> Bool {
        if BSDProcess.name(for: pid) == name {
            return true
        }
        guard let executablePath = BSDProcess.executablePath(for: pid) else { return false }
        return (executablePath as NSString).lastPathComponent == name
    }
}
