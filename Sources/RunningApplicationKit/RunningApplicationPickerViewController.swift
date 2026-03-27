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
            .map { RunningApplication(from: $0) }
        applicationCache = Dictionary(uniqueKeysWithValues: apps.map { ($0.processIdentifier, $0) })
        return apps
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

    override func makeCellView(for tableColumn: NSTableColumn, item: RunningApplication) -> NSView? {
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
        case .bundleIdentifier:
            return tableView.makeView(ofClass: BundleIdentifierTableCellView.self) {
                $0.string = item.bundleIdentifier
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
        }
    }

    override func compareItems(_ lhs: RunningApplication, _ rhs: RunningApplication, columnIdentifier: String) -> ComparisonResult {
        guard let column = Column(rawValue: columnIdentifier) else { return .orderedSame }
        switch column {
        case .icon:
            return .orderedSame
        case .name:
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name)
        case .bundleIdentifier:
            return (lhs.bundleIdentifier ?? "").localizedCaseInsensitiveCompare(rhs.bundleIdentifier ?? "")
        case .pid:
            return lhs.processIdentifier == rhs.processIdentifier ? .orderedSame :
                   lhs.processIdentifier < rhs.processIdentifier ? .orderedAscending : .orderedDescending
        case .architecture:
            return (lhs.architecture?.description ?? "").compare(rhs.architecture?.description ?? "")
        case .sandboxed:
            if lhs.isSandboxed == rhs.isSandboxed { return .orderedSame }
            return lhs.isSandboxed ? .orderedAscending : .orderedDescending
        }
    }

    override func contextMenuItems(for item: RunningApplication) -> [NSMenuItem] {
        var items: [NSMenuItem] = []
        let copyPID = NSMenuItem(title: "Copy PID", action: #selector(copyPIDAction(_:)), keyEquivalent: "")
        copyPID.target = self
        copyPID.representedObject = item
        items.append(copyPID)

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

        for app in currentApps where addedPIDs.contains(app.processIdentifier) {
            applicationCache[app.processIdentifier] = RunningApplication(from: app)
        }

        let orderedItems = currentApps.compactMap { applicationCache[$0.processIdentifier] }
        updateItems(orderedItems, animatingDifferences: true)
    }

    @objc private func copyPIDAction(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? RunningApplication else { return }
        copyToPasteboard("\(item.processIdentifier)")
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
