import AppKit

public final class RunningPickerTabViewController: NSTabViewController {
    // MARK: - Application Column

    public enum ApplicationColumn: String, CaseIterable {
        case icon
        case name
        case bundleIdentifier
        case pid
        case architecture
        case sandboxed

        var title: String {
            switch self {
            case .icon: ""
            case .name: "Name"
            case .bundleIdentifier: "Bundle ID"
            case .pid: "PID"
            case .architecture: "Arch"
            case .sandboxed: "Sandbox"
            }
        }

        var preferredWidth: CGFloat {
            switch self {
            case .icon: 50
            case .name: 200
            case .bundleIdentifier: 200
            case .pid: 50
            case .architecture: 50
            case .sandboxed: 70
            }
        }

        var minWidth: CGFloat? {
            switch self {
            case .name, .bundleIdentifier: nil
            default: preferredWidth
            }
        }

        var maxWidth: CGFloat? {
            switch self {
            case .name, .bundleIdentifier: nil
            default: preferredWidth
            }
        }
    }

    // MARK: - Application Configuration

    public struct ApplicationConfiguration {
        public var title: String
        public var description: String
        public var cancelButtonTitle: String
        public var confirmButtonTitle: String
        public var rowHeight: CGFloat
        public var cellSpacing: CGSize
        public var allowsColumns: [ApplicationColumn]

        public init(
            title: String = "Running Applications",
            description: String = "Select an application",
            cancelButtonTitle: String = "Cancel",
            confirmButtonTitle: String = "Confirm",
            rowHeight: CGFloat = 25,
            cellSpacing: CGSize = .init(width: 0, height: 10),
            allowsColumns: [ApplicationColumn] = ApplicationColumn.allCases
        ) {
            self.title = title
            self.description = description
            self.cancelButtonTitle = cancelButtonTitle
            self.confirmButtonTitle = confirmButtonTitle
            self.rowHeight = rowHeight
            self.cellSpacing = cellSpacing
            self.allowsColumns = allowsColumns
        }

        var baseConfiguration: BaseConfiguration {
            .init(
                title: title,
                description: description,
                cancelButtonTitle: cancelButtonTitle,
                confirmButtonTitle: confirmButtonTitle,
                rowHeight: rowHeight,
                cellSpacing: cellSpacing
            )
        }
    }

    // MARK: - Process Column

    public enum ProcessColumn: String, CaseIterable {
        case icon
        case name
        case pid
        case architecture
        case sandboxed
        case executablePath

        var title: String {
            switch self {
            case .icon: ""
            case .name: "Name"
            case .pid: "PID"
            case .architecture: "Arch"
            case .sandboxed: "Sandbox"
            case .executablePath: "Path"
            }
        }

        var preferredWidth: CGFloat {
            switch self {
            case .icon: 50
            case .name: 200
            case .pid: 50
            case .architecture: 50
            case .sandboxed: 70
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

    // MARK: - Process Configuration

    public struct ProcessConfiguration {
        public var title: String
        public var description: String
        public var cancelButtonTitle: String
        public var confirmButtonTitle: String
        public var rowHeight: CGFloat
        public var cellSpacing: CGSize
        public var allowsColumns: [ProcessColumn]
        public var refreshInterval: TimeInterval

        public init(
            title: String = "Running Processes",
            description: String = "Select a process",
            cancelButtonTitle: String = "Cancel",
            confirmButtonTitle: String = "Confirm",
            rowHeight: CGFloat = 25,
            cellSpacing: CGSize = .init(width: 0, height: 10),
            allowsColumns: [ProcessColumn] = ProcessColumn.allCases,
            refreshInterval: TimeInterval = 2.0
        ) {
            self.title = title
            self.description = description
            self.cancelButtonTitle = cancelButtonTitle
            self.confirmButtonTitle = confirmButtonTitle
            self.rowHeight = rowHeight
            self.cellSpacing = cellSpacing
            self.allowsColumns = allowsColumns
            self.refreshInterval = refreshInterval
        }

        var baseConfiguration: BaseConfiguration {
            .init(
                title: title,
                description: description,
                cancelButtonTitle: cancelButtonTitle,
                confirmButtonTitle: confirmButtonTitle,
                rowHeight: rowHeight,
                cellSpacing: cellSpacing
            )
        }
    }

    // MARK: - Delegate

    public protocol Delegate: AnyObject {
        func runningPickerTabViewController(_ viewController: RunningPickerTabViewController, shouldSelectApplication application: RunningApplication) -> Bool
        func runningPickerTabViewController(_ viewController: RunningPickerTabViewController, didSelectApplication application: RunningApplication)
        func runningPickerTabViewController(_ viewController: RunningPickerTabViewController, didConfirmApplication application: RunningApplication)

        func runningPickerTabViewController(_ viewController: RunningPickerTabViewController, shouldSelectProcess process: RunningProcess) -> Bool
        func runningPickerTabViewController(_ viewController: RunningPickerTabViewController, didSelectProcess process: RunningProcess)
        func runningPickerTabViewController(_ viewController: RunningPickerTabViewController, didConfirmProcess process: RunningProcess)

        func runningPickerTabViewControllerWasCancelled(_ viewController: RunningPickerTabViewController)
    }

    // MARK: - Properties

    public weak var delegate: Delegate?

    private let applicationPickerViewController: RunningApplicationPickerViewController
    private let processPickerViewController: RunningProcessPickerViewController

    public init(
        applicationConfiguration: ApplicationConfiguration = .init(),
        processConfiguration: ProcessConfiguration = .init()
    ) {
        self.applicationPickerViewController = RunningApplicationPickerViewController(configuration: applicationConfiguration)
        self.processPickerViewController = RunningProcessPickerViewController(configuration: processConfiguration)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        preferredContentSize = .init(width: 800, height: 600)

        applicationPickerViewController.delegate = self
        processPickerViewController.delegate = self

        let appTabItem = NSTabViewItem(viewController: applicationPickerViewController)
        appTabItem.label = "Applications"

        let processTabItem = NSTabViewItem(viewController: processPickerViewController)
        processTabItem.label = "Processes"

        addTabViewItem(appTabItem)
        addTabViewItem(processTabItem)

        // Start loading process data in the background immediately so it's
        // ready (or mostly ready) by the time the user switches to the Process tab.
        processPickerViewController.prefetch()
    }
}

// MARK: - RunningApplicationPickerViewController.Delegate

extension RunningPickerTabViewController: RunningApplicationPickerViewController.Delegate {
    func runningApplicationPickerViewController(_ viewController: RunningApplicationPickerViewController, shouldSelectApplication application: RunningApplication) -> Bool {
        delegate?.runningPickerTabViewController(self, shouldSelectApplication: application) ?? true
    }

    func runningApplicationPickerViewController(_ viewController: RunningApplicationPickerViewController, didSelectApplication application: RunningApplication) {
        delegate?.runningPickerTabViewController(self, didSelectApplication: application)
    }

    func runningApplicationPickerViewController(_ viewController: RunningApplicationPickerViewController, didConfirmApplication application: RunningApplication) {
        delegate?.runningPickerTabViewController(self, didConfirmApplication: application)
    }

    func runningApplicationPickerViewControllerWasCancelled(_ viewController: RunningApplicationPickerViewController) {
        delegate?.runningPickerTabViewControllerWasCancelled(self)
    }
}

// MARK: - RunningProcessPickerViewController.Delegate

extension RunningPickerTabViewController: RunningProcessPickerViewController.Delegate {
    func runningProcessPickerViewController(_ viewController: RunningProcessPickerViewController, shouldSelectProcess process: RunningProcess) -> Bool {
        delegate?.runningPickerTabViewController(self, shouldSelectProcess: process) ?? true
    }

    func runningProcessPickerViewController(_ viewController: RunningProcessPickerViewController, didSelectProcess process: RunningProcess) {
        delegate?.runningPickerTabViewController(self, didSelectProcess: process)
    }

    func runningProcessPickerViewController(_ viewController: RunningProcessPickerViewController, didConfirmProcess process: RunningProcess) {
        delegate?.runningPickerTabViewController(self, didConfirmProcess: process)
    }

    func runningProcessPickerViewControllerWasCancelled(_ viewController: RunningProcessPickerViewController) {
        delegate?.runningPickerTabViewControllerWasCancelled(self)
    }
}

// MARK: - Default Delegate Implementations

extension RunningPickerTabViewController.Delegate {
    public func runningPickerTabViewController(_ viewController: RunningPickerTabViewController, shouldSelectApplication application: RunningApplication) -> Bool { true }
    public func runningPickerTabViewController(_ viewController: RunningPickerTabViewController, didSelectApplication application: RunningApplication) {}
    public func runningPickerTabViewController(_ viewController: RunningPickerTabViewController, didConfirmApplication application: RunningApplication) {}
    public func runningPickerTabViewController(_ viewController: RunningPickerTabViewController, shouldSelectProcess process: RunningProcess) -> Bool { true }
    public func runningPickerTabViewController(_ viewController: RunningPickerTabViewController, didSelectProcess process: RunningProcess) {}
    public func runningPickerTabViewController(_ viewController: RunningPickerTabViewController, didConfirmProcess process: RunningProcess) {}
    public func runningPickerTabViewControllerWasCancelled(_ viewController: RunningPickerTabViewController) {}
}
