import AppKit

public actor RunningApplicationObserver {
    public let observeApplicationBundleID: String

    private var runningApplicationsObservation: NSKeyValueObservation?

    private var didLaunch: @Sendable () -> Void = {}

    private var didTerminate: @Sendable () -> Void = {}

    public init(observeApplicationBundleID: String) {
        self.observeApplicationBundleID = observeApplicationBundleID
    }

    public func start() async {
        runningApplicationsObservation = NSWorkspace.shared.observe(\.runningApplications, options: [.old, .new, .initial]) { [weak self] _, change in
            guard let self else { return }
            Task {
                if change.kind == .insertion, let newValue = change.newValue, newValue.contains(where: { $0.bundleIdentifier == self.observeApplicationBundleID }) {
                    await self.didLaunch()
                } else if change.kind == .removal, let oldValue = change.oldValue, oldValue.contains(where: { $0.bundleIdentifier == self.observeApplicationBundleID }) {
                    await self.didTerminate()
                }
            }
        }
    }

    public func stop() async {
        runningApplicationsObservation?.invalidate()
        runningApplicationsObservation = nil
    }
    
    public func onLaunch(_ handler: @escaping @Sendable () -> Void) async {
        self.didLaunch = handler
    }
    
    public func onTerminate(_ handler: @escaping @Sendable () -> Void) async {
        self.didTerminate = handler
    }
}

extension [NSRunningApplication] {
    public func contains(bundleID: String) -> Bool {
        return self.contains(where: { $0.bundleIdentifier == bundleID })
    }
    
    public func first(bundleID: String) -> NSRunningApplication? {
        return self.first(where: { $0.bundleIdentifier == bundleID })
    }
}
