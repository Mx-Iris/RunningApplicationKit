import AppKit
import RunningApplicationKit

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: NSWindowController!
    private var tabViewController: RunningPickerTabViewController!

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        let tabViewController = RunningPickerTabViewController()
        tabViewController.delegate = self
        self.tabViewController = tabViewController

        let contentViewController = ExampleContentViewController(tabViewController: tabViewController)

        let window = NSWindow(contentViewController: contentViewController)
        window.title = "RunningApplicationKit Demo"
        window.setContentSize(NSSize(width: 900, height: 700))
        window.center()

        windowController = NSWindowController(window: window)
        windowController.showWindow(nil)
    }

    func applicationWillTerminate(_ aNotification: Notification) {}

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

extension AppDelegate: RunningPickerTabViewController.Delegate {
    func runningPickerTabViewController(_ viewController: RunningPickerTabViewController, didConfirmApplication application: RunningApplication) {
        let alert = NSAlert()
        alert.messageText = "Selected Application"
        alert.informativeText = """
        Name: \(application.name)
        PID: \(application.processIdentifier)
        Bundle ID: \(application.bundleIdentifier ?? "N/A")
        Architecture: \(application.architecture?.description ?? "Unknown")
        Sandboxed: \(application.isSandboxed)
        """
        alert.runModal()
    }

    func runningPickerTabViewController(_ viewController: RunningPickerTabViewController, didConfirmProcess process: RunningProcess) {
        let alert = NSAlert()
        alert.messageText = "Selected Process"
        alert.informativeText = """
        Name: \(process.name)
        PID: \(process.processIdentifier)
        Path: \(process.executablePath ?? "N/A")
        """
        alert.runModal()
    }

    func runningPickerTabViewControllerWasCancelled(_ viewController: RunningPickerTabViewController) {
        NSApp.terminate(nil)
    }
}

// MARK: - ExampleContentViewController

/// Wraps the picker tab view controller with a 3-state segmented control that
/// drives the skeleton overlay: Skeleton only, Content only, or both at once.
private final class ExampleContentViewController: NSViewController {
    enum SkeletonMode: Int, CaseIterable {
        case skeleton
        case content
        case both

        var title: String {
            switch self {
            case .skeleton: return "Skeleton"
            case .content: return "Content"
            case .both: return "Both"
            }
        }
    }

    private let tabViewController: RunningPickerTabViewController
    private let segmentedControl: NSSegmentedControl
    private var mode: SkeletonMode = .content

    init(tabViewController: RunningPickerTabViewController) {
        self.tabViewController = tabViewController
        self.segmentedControl = NSSegmentedControl(
            labels: SkeletonMode.allCases.map(\.title),
            trackingMode: .selectOne,
            target: nil,
            action: nil
        )
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        addChild(tabViewController)
        let tabView = tabViewController.view
        tabView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tabView)

        segmentedControl.translatesAutoresizingMaskIntoConstraints = false
        segmentedControl.target = self
        segmentedControl.action = #selector(segmentChanged(_:))
        segmentedControl.selectedSegment = mode.rawValue
        view.addSubview(segmentedControl)

        NSLayoutConstraint.activate([
            segmentedControl.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            segmentedControl.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            tabView.topAnchor.constraint(equalTo: segmentedControl.bottomAnchor, constant: 8),
            tabView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tabView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tabView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        apply(mode: mode)
    }

    @objc private func segmentChanged(_ sender: NSSegmentedControl) {
        guard let newMode = SkeletonMode(rawValue: sender.selectedSegment) else { return }
        mode = newMode
        apply(mode: newMode)
    }

    private func apply(mode: SkeletonMode) {
        switch mode {
        case .skeleton:
            tabViewController.setSkeletonOverlayVisible(true, alpha: 1.0)
        case .content:
            tabViewController.setSkeletonOverlayVisible(false)
        case .both:
            tabViewController.setSkeletonOverlayVisible(true, alpha: 0.5)
        }
    }
}
