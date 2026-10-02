import AppKit

/// Picks one process out of a list.
///
/// By default the list is this machine's process table, refreshed incrementally. Give it
/// a ``RunningItemSource`` instead and it shows whatever that source hands over — which
/// is how ``RunningPickerTabViewController`` offers the processes of a machine this
/// library cannot see.
final class RunningProcessPickerViewController: RunningItemPickerViewController<RunningProcess> {
    typealias Column = RunningPickerTabViewController.ProcessField
    typealias Configuration = RunningPickerTabViewController.ProcessConfiguration

    @MainActor protocol Delegate: AnyObject {
        func runningProcessPickerViewController(_ viewController: RunningProcessPickerViewController, shouldSelectProcess process: RunningProcess) -> Bool
        func runningProcessPickerViewController(_ viewController: RunningProcessPickerViewController, didSelectProcess process: RunningProcess)
        func runningProcessPickerViewController(_ viewController: RunningProcessPickerViewController, didConfirmProcess process: RunningProcess)
        func runningProcessPickerViewControllerWasCancelled(_ viewController: RunningProcessPickerViewController)
        /// Only ever called for a picker built with an ``RunningItemSource``; local
        /// enumeration has nothing to fail at.
        func runningProcessPickerViewController(_ viewController: RunningProcessPickerViewController, didFailToLoadProcesses error: any Error)
    }

    weak var delegate: Delegate?

    private(set) var configuration: Configuration

    /// Supplied by the caller, in which case this picker never touches the local process
    /// table. `nil` is the original behaviour, not a degraded one.
    private let itemSource: AnyRunningItemSource<RunningProcess>?

    private var refreshTimer: Timer?
    private var processCache: [pid_t: RunningProcess] = [:]
    private let backgroundQueue = DispatchQueue(label: "com.runningapplicationkit.process-picker", qos: .userInitiated)
    private var sourceLoadTask: Task<Void, Never>?
    private var hasLoadedFromSource = false

    /// Lists the processes of the machine this code is running on.
    init(configuration: Configuration = .init()) {
        self.configuration = configuration
        self.itemSource = nil
        super.init(nibName: nil, bundle: nil)
    }

    /// Lists whatever `itemSource` supplies, and nothing of this machine.
    ///
    /// Unlike the local list, this one does **not** poll: `loadItems()` may be a round
    /// trip to another machine, and repeating it on the local refresh interval would spend
    /// that round trip every couple of seconds for a list that rarely changes. It loads
    /// once when the picker appears; re-fetching is ``reload()``, on the caller's schedule.
    init(
        itemSource: AnyRunningItemSource<RunningProcess>,
        configuration: Configuration = .init(),
    ) {
        self.configuration = configuration
        self.itemSource = itemSource
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func currentBaseConfiguration() -> BaseConfiguration {
        configuration.baseConfiguration
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        preferredContentSize = .init(width: 800, height: 600)
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        stopRefreshTimer()
        sourceLoadTask?.cancel()
        sourceLoadTask = nil
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        guard itemSource == nil else {
            loadFromSourceIfNeeded()
            return
        }
        startRefreshTimer()
        refreshInBackground()
    }

    /// Fetches the supplied source again. Does nothing for a local picker, which keeps
    /// itself current.
    func reload() {
        guard itemSource != nil else { return }
        hasLoadedFromSource = false
        loadFromSourceIfNeeded()
    }

    /// Switch this tab between the table and list presentations at runtime.
    func updateStyle(_ style: RunningPickerTabViewController.Style) {
        guard configuration.style != style else { return }
        configuration.style = style
        applyStyleChange(baseConfiguration: configuration.baseConfiguration) { [weak self] in
            self?.configureColumns()
        }
    }

    // MARK: - Overrides

    override func loadItems() -> [RunningProcess] {
        // Return whatever has been prefetched so far. If prefetch() was called
        // early (e.g. by TabVC), this may already contain the full process list,
        // avoiding an empty-table flash. Otherwise returns empty and
        // refreshInBackground() will populate the table asynchronously.
        Array(processCache.values)
    }

    override func configureColumns() {
        configureColumns(configuration.allowsFields)
    }

    override func makeCellView(for tableColumn: NSTableColumn, item: RunningProcess) -> NSView? {
        if let sharedView = makeSharedCellView(columnIdentifier: tableColumn.identifier.rawValue, item: item) {
            return sharedView
        }
        guard let column = Column(rawValue: tableColumn.identifier.rawValue) else { return nil }
        switch column {
        case .sandboxed:
            return makeSandboxedCellView(isSandboxed: item.isSandboxed)
        case .executablePath:
            return tableView.makeView(ofClass: ExecutablePathTableCellView.self) {
                $0.string = item.executablePath
            }
        default:
            return nil
        }
    }

    override func fieldValue(_ fieldIdentifier: String, for item: RunningProcess) -> String? {
        if fieldIdentifier == Column.executablePath.rawValue {
            return item.executablePath
        }
        return super.fieldValue(fieldIdentifier, for: item)
    }

    override func compareItems(_ lhs: RunningProcess, _ rhs: RunningProcess, columnIdentifier: String) -> ComparisonResult {
        if let sharedResult = compareSharedItems(lhs, rhs, columnIdentifier: columnIdentifier) {
            return sharedResult
        }
        guard let column = Column(rawValue: columnIdentifier) else { return .orderedSame }
        switch column {
        case .executablePath:
            return (lhs.executablePath ?? "").localizedCaseInsensitiveCompare(rhs.executablePath ?? "")
        default:
            return .orderedSame
        }
    }

    override func contextMenuItems(for item: RunningProcess) -> [NSMenuItem] {
        var items: [NSMenuItem] = [makeCopyPIDMenuItem(for: item)]

        if item.executablePath != nil {
            let copyPath = NSMenuItem(title: "Copy Path", action: #selector(copyPathAction(_:)), keyEquivalent: "")
            copyPath.target = self
            copyPath.representedObject = item
            items.append(copyPath)

            items.append(.separator())
            let showInFinder = NSMenuItem(title: "Show in Finder", action: #selector(showInFinderAction(_:)), keyEquivalent: "")
            showInFinder.target = self
            showInFinder.representedObject = item
            items.append(showInFinder)
        }
        return items
    }

    override func didCancel() {
        delegate?.runningProcessPickerViewControllerWasCancelled(self)
    }

    override func didConfirm(item: RunningProcess) {
        delegate?.runningProcessPickerViewController(self, didConfirmProcess: item)
    }

    override func didSelect(item: RunningProcess) {
        delegate?.runningProcessPickerViewController(self, didSelectProcess: item)
    }

    override func shouldSelect(item: RunningProcess) -> Bool {
        delegate?.runningProcessPickerViewController(self, shouldSelectProcess: item) ?? true
    }

    // MARK: - Supplied Items

    /// The in-flight fetch, for tests to await. The load is a task of its own, so there is
    /// otherwise nothing a caller could wait on.
    var pendingSourceLoad: Task<Void, Never>? { sourceLoadTask }

    private func loadFromSourceIfNeeded() {
        guard let itemSource, !hasLoadedFromSource else { return }
        hasLoadedFromSource = true
        sourceLoadTask?.cancel()
        sourceLoadTask = Task { [weak self] in
            do {
                let items = try await itemSource.loadItems()
                guard !Task.isCancelled else { return }
                self?.apply(suppliedItems: items)
            } catch {
                guard !Task.isCancelled else { return }
                self?.handleSourceFailure(error)
            }
        }
    }

    private func apply(suppliedItems items: [RunningProcess]) {
        processCache = Dictionary(items.map { ($0.processIdentifier, $0) }, uniquingKeysWith: { first, _ in first })
        updateItems(items)
        // An empty answer is a legitimate one, and the base class only hides the skeleton
        // when the first batch is non-empty — so without this a device that lists nothing,
        // or a source that failed, would show placeholder rows forever.
        if isSkeletonVisible {
            setSkeletonVisible(false, animated: true)
        }
    }

    private func handleSourceFailure(_ error: any Error) {
        // Not swallowed: a source that failed and a source that is genuinely empty would
        // otherwise look identical — an empty list with nothing to explain it.
        hasLoadedFromSource = false
        apply(suppliedItems: [])
        delegate?.runningProcessPickerViewController(self, didFailToLoadProcesses: error)
    }

    // MARK: - Timer

    private func startRefreshTimer() {
        guard refreshTimer == nil else { return }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: configuration.refreshInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshInBackground()
            }
        }
    }

    private func stopRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    /// Start background process enumeration early, before the view is loaded.
    /// Called by the parent tab view controller so data is ready when the user switches tabs.
    func prefetch() {
        guard itemSource == nil else { return }
        refreshInBackground()
    }

    private func refreshInBackground() {
        let cachedPIDs = Set(processCache.keys)
        let appPIDs = Set(NSWorkspace.shared.runningApplications.map(\.processIdentifier))

        backgroundQueue.async { [weak self] in
            let currentPIDs = Set(BSDProcess.allPIDs().filter { $0 > 0 && !appPIDs.contains($0) })

            let addedPIDs = currentPIDs.subtracting(cachedPIDs)
            let removedPIDs = cachedPIDs.subtracting(currentPIDs)

            guard !addedPIDs.isEmpty || !removedPIDs.isEmpty else { return }

            var newProcesses: [pid_t: RunningProcess] = [:]
            for pid in addedPIDs {
                if let process = RunningProcessEnumerator.makeProcess(for: pid) {
                    newProcesses[pid] = process
                }
            }

            DispatchQueue.main.async {
                guard let self else { return }
                for pid in removedPIDs {
                    self.processCache.removeValue(forKey: pid)
                }
                for (pid, process) in newProcesses {
                    self.processCache[pid] = process
                }
                if self.isViewLoaded {
                    self.updateItems(Array(self.processCache.values))
                }
            }
        }
    }

    // MARK: - Actions

    @objc private func copyPathAction(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? RunningProcess, let path = item.executablePath else { return }
        copyToPasteboard(path)
    }

    @objc private func showInFinderAction(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? RunningProcess, let path = item.executablePath else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }
}

extension RunningProcessPickerViewController.Delegate {
    func runningProcessPickerViewController(_ viewController: RunningProcessPickerViewController, shouldSelectProcess process: RunningProcess) -> Bool { true }
    func runningProcessPickerViewController(_ viewController: RunningProcessPickerViewController, didSelectProcess process: RunningProcess) {}
    func runningProcessPickerViewController(_ viewController: RunningProcessPickerViewController, didConfirmProcess process: RunningProcess) {}
    func runningProcessPickerViewControllerWasCancelled(_ viewController: RunningProcessPickerViewController) {}
    func runningProcessPickerViewController(_ viewController: RunningProcessPickerViewController, didFailToLoadProcesses error: any Error) {}
}
