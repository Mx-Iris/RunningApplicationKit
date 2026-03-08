import AppKit

final class RunningProcessPickerViewController: RunningItemPickerViewController<RunningProcess> {
    typealias Column = RunningPickerTabViewController.ProcessColumn
    typealias Configuration = RunningPickerTabViewController.ProcessConfiguration

    protocol Delegate: AnyObject {
        func runningProcessPickerViewController(_ viewController: RunningProcessPickerViewController, shouldSelectProcess process: RunningProcess) -> Bool
        func runningProcessPickerViewController(_ viewController: RunningProcessPickerViewController, didSelectProcess process: RunningProcess)
        func runningProcessPickerViewController(_ viewController: RunningProcessPickerViewController, didConfirmProcess process: RunningProcess)
        func runningProcessPickerViewControllerWasCancelled(_ viewController: RunningProcessPickerViewController)
    }

    weak var delegate: Delegate?

    private(set) var configuration: Configuration

    private var refreshTimer: Timer?
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
        reloadData()
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
        RunningProcessEnumerator.listProcesses(excludingApplications: true)
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
            return tableView.makeView(ofClass: LabelTableCellView.self) {
                $0.string = item.name
            }
        case .pid:
            return tableView.makeView(ofClass: LabelTableCellView.self) {
                $0.string = "\(item.processIdentifier)"
            }
        case .architecture:
            return tableView.makeView(ofClass: LabelTableCellView.self) {
                $0.string = item.architecture?.description
            }
        case .sandboxed:
            return tableView.makeView(ofClass: IconTableCellView.self) {
                $0.image = item.isSandboxed ? .checkmarkImage : .xmarkImage
                $0.tintColor = item.isSandboxed ? .systemGreen : .systemRed
            }
        case .executablePath:
            return tableView.makeView(ofClass: LabelTableCellView.self) {
                $0.string = item.executablePath
            }
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
            self?.refreshInBackground()
        }
    }

    private func stopRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    private func refreshInBackground() {
        backgroundQueue.async { [weak self] in
            let items = RunningProcessEnumerator.listProcesses(excludingApplications: true)
            DispatchQueue.main.async {
                guard let self else { return }
                self.updateItems(items)
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
}

extension RunningProcessPickerViewController.Delegate {
    func runningProcessPickerViewController(_ viewController: RunningProcessPickerViewController, shouldSelectProcess process: RunningProcess) -> Bool { true }
    func runningProcessPickerViewController(_ viewController: RunningProcessPickerViewController, didSelectProcess process: RunningProcess) {}
    func runningProcessPickerViewController(_ viewController: RunningProcessPickerViewController, didConfirmProcess process: RunningProcess) {}
    func runningProcessPickerViewControllerWasCancelled(_ viewController: RunningProcessPickerViewController) {}
}
