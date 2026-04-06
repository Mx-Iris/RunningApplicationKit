import AppKit

final class RunningApplicationPickerViewController: RunningItemPickerViewController<RunningApplication> {
    typealias Column = RunningPickerTabViewController.ApplicationColumn
    typealias Configuration = RunningPickerTabViewController.ApplicationConfiguration

    @MainActor protocol Delegate: AnyObject {
        func runningApplicationPickerViewController(_ viewController: RunningApplicationPickerViewController, shouldSelectApplication application: RunningApplication) -> Bool
        func runningApplicationPickerViewController(_ viewController: RunningApplicationPickerViewController, didSelectApplication application: RunningApplication)
        func runningApplicationPickerViewController(_ viewController: RunningApplicationPickerViewController, didConfirmApplication application: RunningApplication)
        func runningApplicationPickerViewControllerWasCancelled(_ viewController: RunningApplicationPickerViewController)
    }

    weak var delegate: Delegate?

    private let workspace = NSWorkspace.shared

    private var runningApplicationObservation: NSKeyValueObservation?
    private var applicationCache: [pid_t: RunningApplication] = [:]
    private var cachedItemPIDs: [pid_t] = []

    private(set) var configuration: Configuration

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
        setupObservation()
    }

    // MARK: - Overrides

    override func loadItems() -> [RunningApplication] {
        let apps = workspace.runningApplications
            .filter { $0.processIdentifier > 0 }
            .map { RunningApplication(from: $0, resolveSandbox: false) }
        applicationCache = Dictionary(uniqueKeysWithValues: apps.map { ($0.processIdentifier, $0) })
        cachedItemPIDs = apps.map(\.processIdentifier)
        resolveSandboxStatusAsync(for: apps)
        return apps
    }

    override func configureColumns() {
        configureColumns(configuration.allowsColumns)
    }

    override func makeCellView(for tableColumn: NSTableColumn, item: RunningApplication) -> NSView? {
        if let sharedView = makeSharedCellView(columnIdentifier: tableColumn.identifier.rawValue, item: item) {
            return sharedView
        }
        guard let column = Column(rawValue: tableColumn.identifier.rawValue) else { return nil }
        switch column {
        case .bundleIdentifier:
            return tableView.makeView(ofClass: BundleIdentifierTableCellView.self) {
                $0.string = item.bundleIdentifier
            }
        case .sandboxed:
            return makeSandboxedCellView(isSandboxed: item.isSandboxed, isLoading: !item.isSandboxResolved)
        default:
            return nil
        }
    }

    override func compareItems(_ lhs: RunningApplication, _ rhs: RunningApplication, columnIdentifier: String) -> ComparisonResult {
        if let sharedResult = compareSharedItems(lhs, rhs, columnIdentifier: columnIdentifier) {
            return sharedResult
        }
        guard let column = Column(rawValue: columnIdentifier) else { return .orderedSame }
        switch column {
        case .bundleIdentifier:
            return (lhs.bundleIdentifier ?? "").localizedCaseInsensitiveCompare(rhs.bundleIdentifier ?? "")
        default:
            return .orderedSame
        }
    }

    override func contextMenuItems(for item: RunningApplication) -> [NSMenuItem] {
        var items: [NSMenuItem] = [makeCopyPIDMenuItem(for: item)]

        if item.bundleIdentifier != nil {
            let copyBundleID = NSMenuItem(title: "Copy Bundle ID", action: #selector(copyBundleIDAction(_:)), keyEquivalent: "")
            copyBundleID.target = self
            copyBundleID.representedObject = item
            items.append(copyBundleID)
        }

        if item.bundleURL != nil {
            items.append(.separator())
            let showInFinder = NSMenuItem(title: "Show in Finder", action: #selector(showInFinderAction(_:)), keyEquivalent: "")
            showInFinder.target = self
            showInFinder.representedObject = item
            items.append(showInFinder)
        }
        return items
    }

    override func didCancel() {
        delegate?.runningApplicationPickerViewControllerWasCancelled(self)
    }

    override func didConfirm(item: RunningApplication) {
        delegate?.runningApplicationPickerViewController(self, didConfirmApplication: item)
    }

    override func didSelect(item: RunningApplication) {
        delegate?.runningApplicationPickerViewController(self, didSelectApplication: item)
    }

    override func shouldSelect(item: RunningApplication) -> Bool {
        delegate?.runningApplicationPickerViewController(self, shouldSelectApplication: item) ?? true
    }

    // MARK: - Sandbox Resolution

    private func resolveSandboxStatusAsync(for applications: [RunningApplication]) {
        let pids = applications.map(\.processIdentifier)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var sandboxResults: [pid_t: Bool] = [:]
            for pid in pids {
                sandboxResults[pid] = BSDProcess.isSandboxed(pid: pid)
            }
            DispatchQueue.main.async {
                guard let self else { return }
                for (processIdentifier, isSandboxed) in sandboxResults {
                    if var application = self.applicationCache[processIdentifier] {
                        application.isSandboxed = isSandboxed
                        application.isSandboxResolved = true
                        self.applicationCache[processIdentifier] = application
                    }
                }
                let orderedItems = self.cachedItemPIDs.compactMap { self.applicationCache[$0] }
                self.updateItems(orderedItems, animatingDifferences: false)
            }
        }
    }

    // MARK: - Private

    private func setupObservation() {
        runningApplicationObservation = workspace.observe(\.runningApplications) { [weak self] _, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.handleRunningApplicationsChange()
            }
        }
    }

    private func handleRunningApplicationsChange() {
        let currentApps = workspace.runningApplications.filter { $0.processIdentifier > 0 }
        let currentPIDs = Set(currentApps.map(\.processIdentifier))
        let cachedPIDs = Set(applicationCache.keys)

        let addedPIDs = currentPIDs.subtracting(cachedPIDs)
        let removedPIDs = cachedPIDs.subtracting(currentPIDs)

        guard !addedPIDs.isEmpty || !removedPIDs.isEmpty else { return }

        for pid in removedPIDs {
            applicationCache.removeValue(forKey: pid)
        }

        var newlyAddedApplications: [RunningApplication] = []
        for app in currentApps where addedPIDs.contains(app.processIdentifier) {
            let runningApplication = RunningApplication(from: app, resolveSandbox: false)
            applicationCache[app.processIdentifier] = runningApplication
            newlyAddedApplications.append(runningApplication)
        }

        cachedItemPIDs = currentApps.map(\.processIdentifier)
        let orderedItems = currentApps.compactMap { applicationCache[$0.processIdentifier] }
        updateItems(orderedItems, animatingDifferences: true)

        if !newlyAddedApplications.isEmpty {
            resolveSandboxStatusAsync(for: newlyAddedApplications)
        }
    }

    @objc private func copyBundleIDAction(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? RunningApplication, let bundleID = item.bundleIdentifier else { return }
        copyToPasteboard(bundleID)
    }

    @objc private func showInFinderAction(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? RunningApplication, let bundleURL = item.bundleURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([bundleURL])
    }
}

extension RunningApplicationPickerViewController.Delegate {
    func runningApplicationPickerViewController(_ viewController: RunningApplicationPickerViewController, shouldSelectApplication application: RunningApplication) -> Bool { true }
    func runningApplicationPickerViewController(_ viewController: RunningApplicationPickerViewController, didSelectApplication application: RunningApplication) {}
    func runningApplicationPickerViewController(_ viewController: RunningApplicationPickerViewController, didConfirmApplication application: RunningApplication) {}
    func runningApplicationPickerViewControllerWasCancelled(_ viewController: RunningApplicationPickerViewController) {}
}

import SwiftUI

@available(macOS 14.0, *)
#Preview(traits: .fixedLayout(width: 800, height: 700)) {
    RunningApplicationPickerViewController()
}
