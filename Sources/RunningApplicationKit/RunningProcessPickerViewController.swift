import AppKit

public final class RunningProcessPickerViewController: RunningItemPickerViewController<RunningProcess> {
    public struct Configuration {
        public var title: String
        public var description: String
        public var cancelButtonTitle: String
        public var confirmButtonTitle: String
        public var rowHeight: CGFloat
        public var allowsColumns: [Column]
        public var cellSpacing: CGSize
        public var refreshInterval: TimeInterval

        public init(
            title: String? = nil,
            description: String? = nil,
            cancelButtonTitle: String? = nil,
            confirmButtonTitle: String? = nil,
            rowHeight: CGFloat? = nil,
            allowsColumns: [Column]? = nil,
            cellSpacing: CGSize? = nil,
            refreshInterval: TimeInterval? = nil
        ) {
            self.title = title ?? "Running Processes"
            self.description = description ?? "Select a process"
            self.cancelButtonTitle = cancelButtonTitle ?? "Cancel"
            self.confirmButtonTitle = confirmButtonTitle ?? "Confirm"
            self.rowHeight = rowHeight ?? 25
            self.allowsColumns = allowsColumns ?? Column.allCases
            self.cellSpacing = cellSpacing ?? .init(width: 0, height: 10)
            self.refreshInterval = refreshInterval ?? 2.0
        }
    }

    public protocol Delegate: AnyObject {
        func runningProcessPickerViewController(_ viewController: RunningProcessPickerViewController, shouldSelectProcess process: RunningProcess) -> Bool
        func runningProcessPickerViewController(_ viewController: RunningProcessPickerViewController, didSelectProcess process: RunningProcess)
        func runningProcessPickerViewController(_ viewController: RunningProcessPickerViewController, didConfirmProcess process: RunningProcess)
        func runningProcessPickerViewControllerWasCancelled(_ viewController: RunningProcessPickerViewController)
    }

    public enum Column: String, CaseIterable {
        case icon
        case name
        case pid
        case architecture
        case executablePath

        var title: String {
            switch self {
            case .icon: ""
            case .name: "Name"
            case .pid: "PID"
            case .architecture: "Arch"
            case .executablePath: "Path"
            }
        }

        var preferredWidth: CGFloat {
            switch self {
            case .icon: 50
            case .name: 200
            case .pid: 50
            case .architecture: 50
            case .executablePath: 300
            }
        }

        var minWidth: CGFloat? {
            switch self {
            case .name, .executablePath: nil
            default: preferredWidth
            }
        }

        var maxWidth: CGFloat? {
            switch self {
            case .name, .executablePath: nil
            default: preferredWidth
            }
        }
    }

    public weak var delegate: Delegate?

    public private(set) var configuration: Configuration

    private var refreshTimer: Timer?

    public init(configuration: Configuration = .init()) {
        self.configuration = configuration
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        preferredContentSize = .init(width: 800, height: 600)
        applyBaseConfiguration(.init(
            title: configuration.title,
            description: configuration.description,
            cancelButtonTitle: configuration.cancelButtonTitle,
            confirmButtonTitle: configuration.confirmButtonTitle,
            rowHeight: configuration.rowHeight,
            cellSpacing: configuration.cellSpacing
        ))
        startRefreshTimer()
        reloadData()
    }

    public override func viewWillDisappear() {
        super.viewWillDisappear()
        stopRefreshTimer()
    }

    public override func viewDidAppear() {
        super.viewDidAppear()
        startRefreshTimer()
        reloadData()
    }

    // MARK: - Overrides

    public override func loadItems() -> [RunningProcess] {
        RunningProcessEnumerator.listProcesses(excludingApplications: true)
    }

    public override func configureColumns() {
        for column in configuration.allowsColumns {
            addTableColumn(
                identifier: column.rawValue,
                title: column.title,
                preferredWidth: column.preferredWidth,
                minWidth: column.minWidth,
                maxWidth: column.maxWidth
            )
        }
    }

    public override func makeCellView(for tableColumn: NSTableColumn, item: RunningProcess) -> NSView? {
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
        case .executablePath:
            return tableView.makeView(ofClass: LabelTableCellView.self) {
                $0.string = item.executablePath
            }
        }
    }

    public override func contextMenuItems(for item: RunningProcess) -> [NSMenuItem] {
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

    public override func didCancel() {
        delegate?.runningProcessPickerViewControllerWasCancelled(self)
    }

    public override func didConfirm(item: RunningProcess) {
        delegate?.runningProcessPickerViewController(self, didConfirmProcess: item)
    }

    public override func didSelect(item: RunningProcess) {
        delegate?.runningProcessPickerViewController(self, didSelectProcess: item)
    }

    public override func shouldSelect(item: RunningProcess) -> Bool {
        delegate?.runningProcessPickerViewController(self, shouldSelectProcess: item) ?? true
    }

    // MARK: - Timer

    private func startRefreshTimer() {
        guard refreshTimer == nil else { return }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: configuration.refreshInterval, repeats: true) { [weak self] _ in
            self?.reloadData()
        }
    }

    private func stopRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    // MARK: - Actions

    @objc private func copyPIDAction(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? RunningProcess else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("\(item.processIdentifier)", forType: .string)
    }

    @objc private func copyPathAction(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? RunningProcess, let path = item.executablePath else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(path, forType: .string)
    }
}

extension RunningProcessPickerViewController.Delegate {
    public func runningProcessPickerViewController(_ viewController: RunningProcessPickerViewController, shouldSelectProcess process: RunningProcess) -> Bool { true }
    public func runningProcessPickerViewController(_ viewController: RunningProcessPickerViewController, didSelectProcess process: RunningProcess) {}
    public func runningProcessPickerViewController(_ viewController: RunningProcessPickerViewController, didConfirmProcess process: RunningProcess) {}
    public func runningProcessPickerViewControllerWasCancelled(_ viewController: RunningProcessPickerViewController) {}
}
