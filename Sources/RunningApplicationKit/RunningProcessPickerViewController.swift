import AppKit

final class RunningProcessPickerViewController: RunningItemPickerViewController<RunningProcess> {
    typealias Column = RunningPickerTabViewController.ProcessColumn
    typealias Configuration = RunningPickerTabViewController.ProcessConfiguration

    @MainActor protocol Delegate: AnyObject {
        func runningProcessPickerViewController(_ viewController: RunningProcessPickerViewController, shouldSelectProcess process: RunningProcess) -> Bool
        func runningProcessPickerViewController(_ viewController: RunningProcessPickerViewController, didSelectProcess process: RunningProcess)
        func runningProcessPickerViewController(_ viewController: RunningProcessPickerViewController, didConfirmProcess process: RunningProcess)
        func runningProcessPickerViewControllerWasCancelled(_ viewController: RunningProcessPickerViewController)
    }

    weak var delegate: Delegate?

    private(set) var configuration: Configuration

    private var refreshTimer: Timer?
    private var processCache: [pid_t: RunningProcess] = [:]
    private let backgroundQueue = DispatchQueue(label: "com.runningapplicationkit.process-picker", qos: .userInitiated)

    init(configuration: Configuration = .init()) {
        self.configuration = configuration
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        preferredContentSize = .init(width: 800, height: 600)
        applyBaseConfiguration(configuration.baseConfiguration)
        startRefreshTimer()
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        stopRefreshTimer()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        startRefreshTimer()
        refreshInBackground()
    }

    // MARK: - Overrides

    override func loadItems() -> [RunningProcess] {
        let processes = RunningProcessEnumerator.listProcesses(excludingApplications: true)
        processCache = Dictionary(uniqueKeysWithValues: processes.map { ($0.processIdentifier, $0) })
        return processes
    }

    override func configureColumns() {
        for column in configuration.allowsColumns {
            addTableColumn(
                identifier: column.rawValue,
                title: column.title,
                preferredWidth: column.preferredWidth,
                minWidth: column.minWidth,
                maxWidth: column.maxWidth,
                headerAlignment: column == .sandboxed ? .center : nil
            )
        }
    }

    override func makeCellView(for tableColumn: NSTableColumn, item: RunningProcess) -> NSView? {
        guard let column = Column(rawValue: tableColumn.identifier.rawValue) else { return nil }
        switch column {
        case .icon:
            return tableView.makeView(ofClass: IconTableCellView.self) {
                $0.image = item.icon
            }
        case .name:
            return tableView.makeView(ofClass: NameTableCellView.self) {
                $0.string = item.name
            }
        case .pid:
            return tableView.makeView(ofClass: PIDTableCellView.self) {
                $0.string = "\(item.processIdentifier)"
            }
        case .architecture:
            return tableView.makeView(ofClass: ArchitectureTableCellView.self) {
                $0.string = item.architecture?.description
            }
        case .sandboxed:
            return tableView.makeView(ofClass: StatusIconTableCellView.self) {
                $0.image = item.isSandboxed ? .checkmarkImage : .xmarkImage
                $0.tintColor = item.isSandboxed ? .systemGreen : .systemRed
            }
        case .executablePath:
            return tableView.makeView(ofClass: ExecutablePathTableCellView.self) {
                $0.string = item.executablePath
            }
        }
    }

    override func compareItems(_ lhs: RunningProcess, _ rhs: RunningProcess, columnIdentifier: String) -> ComparisonResult {
        guard let column = Column(rawValue: columnIdentifier) else { return .orderedSame }
        switch column {
        case .icon:
            return .orderedSame
        case .name:
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name)
        case .pid:
            return lhs.processIdentifier == rhs.processIdentifier ? .orderedSame :
                   lhs.processIdentifier < rhs.processIdentifier ? .orderedAscending : .orderedDescending
        case .architecture:
            return (lhs.architecture?.description ?? "").compare(rhs.architecture?.description ?? "")
        case .sandboxed:
            if lhs.isSandboxed == rhs.isSandboxed { return .orderedSame }
            return lhs.isSandboxed ? .orderedAscending : .orderedDescending
        case .executablePath:
            return (lhs.executablePath ?? "").localizedCaseInsensitiveCompare(rhs.executablePath ?? "")
        }
    }

    override func contextMenuItems(for item: RunningProcess) -> [NSMenuItem] {
        var items: [NSMenuItem] = []
        let copyPID = NSMenuItem(title: "Copy PID", action: #selector(copyPIDAction(_:)), keyEquivalent: "")
        copyPID.target = self
        copyPID.representedObject = item
        items.append(copyPID)

        if item.executablePath != nil {
            let copyPath = NSMenuItem(title: "Copy Path", action: #selector(copyPathAction(_:)), keyEquivalent: "")
            copyPath.target = self
            copyPath.representedObject = item
            items.append(copyPath)
        }

        if item.executablePath != nil {
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

    private func refreshInBackground() {
        let cachedPIDs = Set(processCache.keys)
        let appPIDs = Set(NSWorkspace.shared.runningApplications.map(\.processIdentifier))

        backgroundQueue.async { [weak self] in
            let currentPIDs = Set(BSDProcess.allPIDs().filter { $0 > 0 && !appPIDs.contains($0) })

            let addedPIDs = currentPIDs.subtracting(cachedPIDs)
            let removedPIDs = cachedPIDs.subtracting(currentPIDs)

            guard !addedPIDs.isEmpty || !removedPIDs.isEmpty else { return }

            // Only create RunningProcess for newly appeared PIDs (expensive)
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
                self.updateItems(Array(self.processCache.values))
            }
        }
    }

    // MARK: - Actions

    @objc private func copyPIDAction(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? RunningProcess else { return }
        copyToPasteboard("\(item.processIdentifier)")
    }

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
}
