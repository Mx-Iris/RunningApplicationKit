import AppKit
import LaunchServicesPrivate

public final class RunningApplicationPickerViewController: RunningItemPickerViewController<RunningApplication> {
    public struct Configuration {
        public var title: String
        public var description: String
        public var cancelButtonTitle: String
        public var confirmButtonTitle: String
        public var rowHeight: CGFloat
        public var allowsColumns: [Column]
        public var cellSpacing: CGSize

        public init(
            title: String? = nil,
            description: String? = nil,
            cancelButtonTitle: String? = nil,
            confirmButtonTitle: String? = nil,
            rowHeight: CGFloat? = nil,
            allowsColumns: [Column]? = nil,
            cellSpacing: CGSize? = nil
        ) {
            self.title = title ?? "Running Applications"
            self.description = description ?? "Select an application"
            self.cancelButtonTitle = cancelButtonTitle ?? "Cancel"
            self.confirmButtonTitle = confirmButtonTitle ?? "Confirm"
            self.rowHeight = rowHeight ?? 25
            self.allowsColumns = allowsColumns ?? Column.allCases
            self.cellSpacing = cellSpacing ?? .init(width: 0, height: 10)
        }
    }

    public protocol Delegate: AnyObject {
        func runningApplicationPickerViewController(_ viewController: RunningApplicationPickerViewController, shouldSelectApplication application: RunningApplication) -> Bool
        func runningApplicationPickerViewController(_ viewController: RunningApplicationPickerViewController, didSelectApplication application: RunningApplication)
        func runningApplicationPickerViewController(_ viewController: RunningApplicationPickerViewController, didConfirmApplication application: RunningApplication)
        func runningApplicationPickerViewControllerWasCancelled(_ viewController: RunningApplicationPickerViewController)
    }

    public enum Column: String, CaseIterable {
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

    public weak var delegate: Delegate?

    private let workspace = NSWorkspace.shared

    private var runningApplicationObservation: NSKeyValueObservation?

    public private(set) var configuration: Configuration

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
        setupObservation()
        reloadData()
    }

    // MARK: - Overrides

    public override func loadItems() -> [RunningApplication] {
        workspace.runningApplications
            .filter { $0.processIdentifier > 0 }
            .map { RunningApplication(from: $0) }
    }

    public override func configureColumns() {
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

    public override func makeCellView(for tableColumn: NSTableColumn, item: RunningApplication) -> NSView? {
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
        case .bundleIdentifier:
            return tableView.makeView(ofClass: LabelTableCellView.self) {
                $0.string = item.bundleIdentifier
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
        }
    }

    public override func contextMenuItems(for item: RunningApplication) -> [NSMenuItem] {
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
        return items
    }

    public override func didCancel() {
        delegate?.runningApplicationPickerViewControllerWasCancelled(self)
    }

    public override func didConfirm(item: RunningApplication) {
        delegate?.runningApplicationPickerViewController(self, didConfirmApplication: item)
    }

    public override func didSelect(item: RunningApplication) {
        delegate?.runningApplicationPickerViewController(self, didSelectApplication: item)
    }

    public override func shouldSelect(item: RunningApplication) -> Bool {
        delegate?.runningApplicationPickerViewController(self, shouldSelectApplication: item) ?? true
    }

    // MARK: - Private

    private func setupObservation() {
        runningApplicationObservation = workspace.observe(\.runningApplications) { [weak self] _, _ in
            guard let self else { return }
            self.reloadData()
        }
    }

    @objc private func copyPIDAction(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? RunningApplication else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("\(item.processIdentifier)", forType: .string)
    }

    @objc private func copyBundleIDAction(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? RunningApplication, let bundleID = item.bundleIdentifier else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(bundleID, forType: .string)
    }
}

extension RunningApplicationPickerViewController.Delegate {
    public func runningApplicationPickerViewController(_ viewController: RunningApplicationPickerViewController, shouldSelectApplication application: RunningApplication) -> Bool { true }
    public func runningApplicationPickerViewController(_ viewController: RunningApplicationPickerViewController, didSelectApplication application: RunningApplication) {}
    public func runningApplicationPickerViewController(_ viewController: RunningApplicationPickerViewController, didConfirmApplication application: RunningApplication) {}
    public func runningApplicationPickerViewControllerWasCancelled(_ viewController: RunningApplicationPickerViewController) {}
}

import SwiftUI

@available(macOS 14.0, *)
#Preview(traits: .fixedLayout(width: 800, height: 700)) {
    RunningApplicationPickerViewController()
}
