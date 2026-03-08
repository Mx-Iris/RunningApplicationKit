# Process-Level Support Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add process-level support to RunningApplicationKit — a `RunningProcess` model, process observer, process picker, and a tab-based container combining app and process pickers.

**Architecture:** Extract common picker logic into a generic base class `RunningItemPickerViewController<Item>`. Both `RunningApplicationPickerViewController` and `RunningProcessPickerViewController` inherit from it. A `RunningPickerTabViewController` wraps both in tabs. Shared protocol `RunningItem` unifies `RunningApplication` and `RunningProcess` models. Process enumeration uses BSD `proc_listpids`/`proc_pidpath`.

**Tech Stack:** Swift 5.10, AppKit, macOS 11+, BSD `libproc.h` APIs

---

### Task 1: Extract Extensions to Separate Files

Extract `NSTableView`, `NSRunningApplication`, and `NSImage` extensions out of `RunningApplicationPickerViewController.swift` into their own files.

**Files:**
- Create: `Sources/RunningApplicationKit/Extensions/NSTableView+Extensions.swift`
- Create: `Sources/RunningApplicationKit/Extensions/NSRunningApplication+Extensions.swift`
- Create: `Sources/RunningApplicationKit/Extensions/NSImage+Extensions.swift`
- Modify: `Sources/RunningApplicationKit/RunningApplicationPickerViewController.swift` (remove lines 498-570)

**Step 1: Create NSTableView+Extensions.swift**

```swift
import AppKit

extension NSTableView {
    func makeView<View: NSView>(ofClass viewClass: View.Type, modify: ((View) -> Void)? = nil) -> View {
        if let cellView = makeView(withIdentifier: .init(String(describing: viewClass)), owner: nil) as? View {
            modify?(cellView)
            return cellView
        } else {
            let cellView = View()
            cellView.identifier = .init(String(describing: viewClass))
            modify?(cellView)
            return cellView
        }
    }
}
```

**Step 2: Create NSRunningApplication+Extensions.swift**

```swift
import AppKit
import LaunchServicesPrivate

extension NSRunningApplication {
    var applicationProxy: LSApplicationProxy? {
        guard let bundleIdentifier else { return nil }
        return LSApplicationProxy(forIdentifier: bundleIdentifier)
    }

    var isSandboxed: Bool {
        guard let entitlements = applicationProxy?.entitlements else { return false }
        guard let isSandboxed = entitlements["com.apple.security.app-sandbox"] as? Bool else { return false }
        return isSandboxed
    }
}
```

**Step 3: Create NSImage+Extensions.swift**

```swift
import AppKit

extension NSImage {
    static let checkmarkImage = NSImage(systemSymbolName: "checkmark.circle", accessibilityDescription: nil)
    static let xmarkImage = NSImage(systemSymbolName: "xmark.circle", accessibilityDescription: nil)
}
```

**Step 4: Remove extracted code from RunningApplicationPickerViewController.swift**

Remove the `extension NSTableView` block (lines 498-510), `extension NSRunningApplication` block (lines 512-565), and `extension NSImage` block (lines 567-570) from the file.

**Step 5: Build**

```bash
swift package update && swift build 2>&1 | xcsift
```

**Step 6: Commit**

```bash
git add Sources/RunningApplicationKit/Extensions/
git add Sources/RunningApplicationKit/RunningApplicationPickerViewController.swift
git commit -m "refactor: Extract extensions to separate files"
```

---

### Task 2: Create Architecture Enum (Standalone)

Move `Architecture` from being nested in `NSRunningApplication` extension to a standalone public enum, so both `RunningApplication` and `RunningProcess` can use it.

**Files:**
- Create: `Sources/RunningApplicationKit/Architecture.swift`
- Modify: `Sources/RunningApplicationKit/Extensions/NSRunningApplication+Extensions.swift`

**Step 1: Create Architecture.swift**

```swift
import Foundation

public enum Architecture: CustomStringConvertible, Hashable, Sendable {
    case x86_64
    case arm64
    case i386
    case ppc
    case ppc64
    case unknown

    public var description: String {
        switch self {
        case .x86_64:
            "x64"
        case .arm64:
            "arm64"
        case .i386:
            "i386"
        case .ppc:
            "PPC"
        case .ppc64:
            "PPC64"
        case .unknown:
            "Unknown"
        }
    }
}
```

**Step 2: Update NSRunningApplication+Extensions.swift**

Add an `architecture` computed property that maps `executableArchitecture` to the standalone `Architecture` enum. Remove the old nested `Architecture` enum definition from the extension.

```swift
import AppKit
import LaunchServicesPrivate

extension NSRunningApplication {
    var architecture: Architecture {
        switch executableArchitecture {
        case NSBundleExecutableArchitectureARM64:
            return .arm64
        case NSBundleExecutableArchitectureX86_64:
            return .x86_64
        case NSBundleExecutableArchitectureI386:
            return .i386
        case NSBundleExecutableArchitecturePPC:
            return .ppc
        case NSBundleExecutableArchitecturePPC64:
            return .ppc64
        default:
            return .unknown
        }
    }

    var applicationProxy: LSApplicationProxy? {
        guard let bundleIdentifier else { return nil }
        return LSApplicationProxy(forIdentifier: bundleIdentifier)
    }

    var isSandboxed: Bool {
        guard let entitlements = applicationProxy?.entitlements else { return false }
        guard let isSandboxed = entitlements["com.apple.security.app-sandbox"] as? Bool else { return false }
        return isSandboxed
    }
}
```

**Step 3: Update RunningApplicationPickerViewController.swift**

Change any references from `NSRunningApplication.Architecture` to just `Architecture` (the `architecture` computed property already returns this type, so cell rendering code should work as-is).

**Step 4: Build**

```bash
swift build 2>&1 | xcsift
```

**Step 5: Commit**

```bash
git add Sources/RunningApplicationKit/Architecture.swift
git add Sources/RunningApplicationKit/Extensions/NSRunningApplication+Extensions.swift
git add Sources/RunningApplicationKit/RunningApplicationPickerViewController.swift
git commit -m "refactor: Extract Architecture enum to standalone type"
```

---

### Task 3: Create RunningItem Protocol and RunningApplication Model

**Files:**
- Create: `Sources/RunningApplicationKit/RunningItem.swift`
- Create: `Sources/RunningApplicationKit/RunningApplication.swift`

**Step 1: Create RunningItem.swift**

```swift
import AppKit

public protocol RunningItem: Hashable, Sendable {
    var pid: pid_t { get }
    var name: String { get }
    var icon: NSImage? { get }
    var architecture: Architecture? { get }
}
```

**Step 2: Create RunningApplication.swift**

```swift
import AppKit

public struct RunningApplication: RunningItem {
    public let pid: pid_t
    public let name: String
    public let bundleIdentifier: String?
    public let icon: NSImage?
    public let architecture: Architecture?
    public let isSandboxed: Bool

    public init(from app: NSRunningApplication) {
        self.pid = app.processIdentifier
        self.name = app.localizedName ?? "Unknown"
        self.bundleIdentifier = app.bundleIdentifier
        self.icon = app.icon
        self.architecture = app.architecture
        self.isSandboxed = app.isSandboxed
    }

    // Hashable: identity by PID
    public func hash(into hasher: inout Hasher) {
        hasher.combine(pid)
    }

    public static func == (lhs: RunningApplication, rhs: RunningApplication) -> Bool {
        lhs.pid == rhs.pid
    }
}
```

**Step 3: Build**

```bash
swift build 2>&1 | xcsift
```

**Step 4: Commit**

```bash
git add Sources/RunningApplicationKit/RunningItem.swift
git add Sources/RunningApplicationKit/RunningApplication.swift
git commit -m "feat: Add RunningItem protocol and RunningApplication model"
```

---

### Task 4: Create RunningProcess Model

**Files:**
- Create: `Sources/RunningApplicationKit/RunningProcess.swift`

**Step 1: Create RunningProcess.swift**

```swift
import AppKit
import Darwin

public struct RunningProcess: RunningItem {
    public let pid: pid_t
    public let name: String
    public let executablePath: String?
    public let icon: NSImage?
    public let architecture: Architecture?

    public init(pid: pid_t, name: String, executablePath: String?, icon: NSImage?, architecture: Architecture?) {
        self.pid = pid
        self.name = name
        self.executablePath = executablePath
        self.icon = icon
        self.architecture = architecture
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(pid)
    }

    public static func == (lhs: RunningProcess, rhs: RunningProcess) -> Bool {
        lhs.pid == rhs.pid
    }
}

public enum RunningProcessEnumerator {
    /// List all running processes, excluding those that are NSRunningApplications.
    public static func listProcesses(excludingApplications: Bool = true) -> [RunningProcess] {
        let appPIDs: Set<pid_t>
        if excludingApplications {
            appPIDs = Set(NSWorkspace.shared.runningApplications.map(\.processIdentifier))
        } else {
            appPIDs = []
        }

        let bufferSize = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard bufferSize > 0 else { return [] }

        let pidCount = Int(bufferSize) / MemoryLayout<pid_t>.size
        var pids = [pid_t](repeating: 0, count: pidCount)
        let actualSize = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, bufferSize)
        guard actualSize > 0 else { return [] }

        let actualCount = Int(actualSize) / MemoryLayout<pid_t>.size
        var processes: [RunningProcess] = []

        for i in 0..<actualCount {
            let pid = pids[i]
            guard pid > 0, !appPIDs.contains(pid) else { continue }

            // Get process name
            var nameBuffer = [CChar](repeating: 0, count: Int(MAXCOMLEN) + 1)
            let nameLength = proc_name(pid, &nameBuffer, UInt32(nameBuffer.count))
            guard nameLength > 0 else { continue }
            let name = String(cString: nameBuffer)

            // Get executable path
            var pathBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
            let pathLength = proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count))
            let executablePath: String? = pathLength > 0 ? String(cString: pathBuffer) : nil

            // Get icon from executable path
            let icon: NSImage?
            if let executablePath {
                icon = NSWorkspace.shared.icon(forFile: executablePath)
            } else {
                icon = nil
            }

            let process = RunningProcess(
                pid: pid,
                name: name,
                executablePath: executablePath,
                icon: icon,
                architecture: nil  // Architecture detection for arbitrary processes is non-trivial
            )
            processes.append(process)
        }

        return processes.sorted { $0.pid < $1.pid }
    }
}
```

**Step 2: Build**

```bash
swift build 2>&1 | xcsift
```

**Step 3: Commit**

```bash
git add Sources/RunningApplicationKit/RunningProcess.swift
git commit -m "feat: Add RunningProcess model with BSD proc API"
```

---

### Task 5: Create RunningProcessObserver

**Files:**
- Create: `Sources/RunningApplicationKit/RunningProcessObserver.swift`

**Step 1: Create RunningProcessObserver.swift**

```swift
import AppKit
import Darwin

public actor RunningProcessObserver {
    public enum Target: Sendable {
        case pid(pid_t)
        case name(String)
        case executablePath(String)
    }

    public let target: Target
    public let pollingInterval: TimeInterval

    private var pollingTask: Task<Void, Never>?
    private var knownPIDs: Set<pid_t> = []
    private var didLaunch: @Sendable () -> Void = {}
    private var didTerminate: @Sendable () -> Void = {}

    public init(target: Target, pollingInterval: TimeInterval = 2.0) {
        self.target = target
        self.pollingInterval = pollingInterval
    }

    public func onLaunch(_ handler: @escaping @Sendable () -> Void) {
        self.didLaunch = handler
    }

    public func onTerminate(_ handler: @escaping @Sendable () -> Void) {
        self.didTerminate = handler
    }

    public func start() {
        pollingTask = Task { [weak self] in
            guard let self else { return }
            // Initial scan
            let initialPIDs = await self.findMatchingPIDs()
            await self.updateKnownPIDs(initialPIDs)

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(pollingInterval * 1_000_000_000))
                guard !Task.isCancelled else { break }
                let currentPIDs = await self.findMatchingPIDs()
                await self.diffAndNotify(currentPIDs)
            }
        }
    }

    public func stop() {
        pollingTask?.cancel()
        pollingTask = nil
        knownPIDs = []
    }

    private func updateKnownPIDs(_ pids: Set<pid_t>) {
        knownPIDs = pids
    }

    private func diffAndNotify(_ currentPIDs: Set<pid_t>) {
        let launched = currentPIDs.subtracting(knownPIDs)
        let terminated = knownPIDs.subtracting(currentPIDs)

        if !launched.isEmpty {
            didLaunch()
        }
        if !terminated.isEmpty {
            didTerminate()
        }

        knownPIDs = currentPIDs
    }

    private nonisolated func findMatchingPIDs() async -> Set<pid_t> {
        let bufferSize = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard bufferSize > 0 else { return [] }

        let pidCount = Int(bufferSize) / MemoryLayout<pid_t>.size
        var pids = [pid_t](repeating: 0, count: pidCount)
        let actualSize = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, bufferSize)
        guard actualSize > 0 else { return [] }

        let actualCount = Int(actualSize) / MemoryLayout<pid_t>.size
        var matchingPIDs: Set<pid_t> = []

        let target = await self.target

        for i in 0..<actualCount {
            let pid = pids[i]
            guard pid > 0 else { continue }

            switch target {
            case .pid(let targetPID):
                if pid == targetPID {
                    matchingPIDs.insert(pid)
                }
            case .name(let targetName):
                var nameBuffer = [CChar](repeating: 0, count: Int(MAXCOMLEN) + 1)
                let nameLength = proc_name(pid, &nameBuffer, UInt32(nameBuffer.count))
                if nameLength > 0 {
                    let name = String(cString: nameBuffer)
                    if name == targetName {
                        matchingPIDs.insert(pid)
                    }
                }
            case .executablePath(let targetPath):
                var pathBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
                let pathLength = proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count))
                if pathLength > 0 {
                    let path = String(cString: pathBuffer)
                    if path == targetPath {
                        matchingPIDs.insert(pid)
                    }
                }
            }
        }

        return matchingPIDs
    }
}
```

**Step 2: Build**

```bash
swift build 2>&1 | xcsift
```

**Step 3: Commit**

```bash
git add Sources/RunningApplicationKit/RunningProcessObserver.swift
git commit -m "feat: Add RunningProcessObserver with polling-based detection"
```

---

### Task 6: Extract Cell Views to Shared File

The cell views (`TableCellView`, `IconTableCellView`, `LabelTableCellView`, `CheckboxTableCellView`) are currently private classes nested inside `RunningApplicationPickerViewController`. Extract them to a shared file so both picker subclasses can use them.

**Files:**
- Create: `Sources/RunningApplicationKit/TableCellViews.swift`
- Modify: `Sources/RunningApplicationKit/RunningApplicationPickerViewController.swift` (remove lines 382-480)

**Step 1: Create TableCellViews.swift**

```swift
import AppKit

class TableCellView: NSTableCellView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

class IconTableCellView: TableCellView {
    var tintColor: NSColor? {
        didSet {
            iconImageView.contentTintColor = tintColor
        }
    }

    var image: NSImage? {
        didSet {
            iconImageView.image = image
        }
    }

    private let iconImageView = NSImageView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(iconImageView)
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            iconImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconImageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconImageView.heightAnchor.constraint(equalTo: heightAnchor),
            iconImageView.widthAnchor.constraint(equalTo: heightAnchor),
        ])
    }
}

class LabelTableCellView: TableCellView {
    var string: String? {
        didSet {
            label.stringValue = string ?? ""
            toolTip = label.stringValue
        }
    }

    var attributedString: NSAttributedString? {
        didSet {
            label.attributedStringValue = attributedString ?? NSAttributedString()
            toolTip = label.attributedStringValue.string
        }
    }

    private let label = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 12, weight: .regular)
        label.lineBreakMode = .byTruncatingTail
        NSLayoutConstraint.activate([
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            label.topAnchor.constraint(greaterThanOrEqualTo: topAnchor),
            label.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
        ])
    }
}

class CheckboxTableCellView: TableCellView {
    var isChecked: Bool = false {
        didSet {
            checkbox.state = isChecked ? .on : .off
        }
    }

    var isEnabled: Bool = false {
        didSet {
            checkbox.isEnabled = isEnabled
        }
    }

    private let checkbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(checkbox)
        checkbox.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            checkbox.centerYAnchor.constraint(equalTo: centerYAnchor),
            checkbox.centerXAnchor.constraint(equalTo: centerXAnchor),
        ])
    }
}
```

**Step 2: Remove cell view classes from RunningApplicationPickerViewController.swift**

Remove the entire `extension RunningApplicationPickerViewController` block (lines 382-480) that contains the cell view classes.

**Step 3: Build**

```bash
swift build 2>&1 | xcsift
```

**Step 4: Commit**

```bash
git add Sources/RunningApplicationKit/TableCellViews.swift
git add Sources/RunningApplicationKit/RunningApplicationPickerViewController.swift
git commit -m "refactor: Extract cell views to shared file"
```

---

### Task 7: Create RunningItemPickerViewController Base Class

Extract the common picker UI and logic into a generic base class.

**Files:**
- Create: `Sources/RunningApplicationKit/RunningItemPickerViewController.swift`

**Step 1: Create RunningItemPickerViewController.swift**

```swift
import AppKit

open class RunningItemPickerViewController<Item: RunningItem>: NSViewController, NSTableViewDelegate {
    public struct BaseConfiguration {
        public var title: String
        public var description: String
        public var cancelButtonTitle: String
        public var confirmButtonTitle: String
        public var rowHeight: CGFloat
        public var cellSpacing: CGSize

        public init(
            title: String = "",
            description: String = "",
            cancelButtonTitle: String = "Cancel",
            confirmButtonTitle: String = "Confirm",
            rowHeight: CGFloat = 25,
            cellSpacing: CGSize = .init(width: 0, height: 10)
        ) {
            self.title = title
            self.description = description
            self.cancelButtonTitle = cancelButtonTitle
            self.confirmButtonTitle = confirmButtonTitle
            self.rowHeight = rowHeight
            self.cellSpacing = cellSpacing
        }
    }

    private enum Section: CaseIterable {
        case main
    }

    private typealias DataSource = NSTableViewDiffableDataSource<Section, Item>
    private typealias Snapshot = NSDiffableDataSourceSnapshot<Section, Item>

    // MARK: - UI

    let scrollView = NSScrollView()
    let tableView = NSTableView()
    let titleLabel = NSTextField(labelWithString: "")
    let descriptionLabel = NSTextField(labelWithString: "")
    private(set) lazy var cancelButton = NSButton(title: "", target: self, action: #selector(cancelAction))
    private(set) lazy var confirmButton = NSButton(title: "", target: self, action: #selector(confirmAction))
    let topStackView = NSStackView()
    let titleStackView = NSStackView()
    let bottomStackView = NSStackView()
    let searchField = NSSearchField()

    private lazy var dataSource = makeDataSource()

    // MARK: - Subclass Hooks

    /// Return the items to display. Called on each reload.
    open func loadItems() -> [Item] { [] }

    /// Filter items based on search text. Default implementation filters by name.
    open func filterItems(_ items: [Item], searchText: String) -> [Item] {
        guard !searchText.isEmpty else { return items }
        return items.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    /// Configure the table columns. Subclasses must call `addTableColumn` for each column.
    open func configureColumns() {}

    /// Return a cell view for the given column and item.
    open func makeCellView(for tableColumn: NSTableColumn, item: Item) -> NSView? { nil }

    /// Return context menu items for the given item.
    open func contextMenuItems(for item: Item) -> [NSMenuItem] { [] }

    /// Called when the user clicks Cancel.
    open func didCancel() {}

    /// Called when the user confirms selection.
    open func didConfirm(item: Item) {}

    /// Called when selection changes.
    open func didSelect(item: Item) {}

    /// Return whether the given item should be selectable.
    open func shouldSelect(item: Item) -> Bool { true }

    /// Return the type-select string for the given item. Default returns name.
    open func typeSelectString(for item: Item) -> String? { item.name }

    // MARK: - Lifecycle

    public override func loadView() {
        view = NSView()
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        view.addSubview(scrollView)
        view.addSubview(topStackView)
        view.addSubview(bottomStackView)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.scrollerStyle = .overlay
        topStackView.translatesAutoresizingMaskIntoConstraints = false
        bottomStackView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            topStackView.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            topStackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            topStackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            scrollView.topAnchor.constraint(equalTo: topStackView.bottomAnchor, constant: 20),
            scrollView.bottomAnchor.constraint(equalTo: bottomStackView.topAnchor, constant: -20),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            bottomStackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            bottomStackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            bottomStackView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20),

            searchField.widthAnchor.constraint(equalToConstant: 300),
        ])

        topStackView.orientation = .horizontal
        topStackView.spacing = 10
        topStackView.distribution = .fill
        topStackView.alignment = .top
        topStackView.addArrangedSubview(titleStackView)
        topStackView.addArrangedSubview(searchField)

        titleStackView.orientation = .vertical
        titleStackView.spacing = 10
        titleStackView.distribution = .fill
        titleStackView.alignment = .leading
        titleStackView.addArrangedSubview(titleLabel)
        titleStackView.addArrangedSubview(descriptionLabel)

        bottomStackView.orientation = .horizontal
        bottomStackView.spacing = 10
        bottomStackView.distribution = .gravityAreas
        bottomStackView.alignment = .centerY
        bottomStackView.addView(cancelButton, in: .trailing)
        bottomStackView.addView(confirmButton, in: .trailing)
        bottomStackView.setCustomSpacing(12, after: cancelButton)

        if #available(macOS 26.0, *) {
            searchField.controlSize = .extraLarge
        } else {
            searchField.controlSize = .large
        }
        searchField.target = self
        searchField.action = #selector(searchTextFieldDidChange(_:))

        titleLabel.font = .systemFont(ofSize: 20, weight: .bold)
        titleLabel.textColor = .labelColor

        descriptionLabel.font = .systemFont(ofSize: 14, weight: .regular)
        descriptionLabel.textColor = .secondaryLabelColor

        cancelButton.keyEquivalent = "\u{1b}"

        confirmButton.keyEquivalent = "\r"
        confirmButton.isEnabled = false

        scrollView.documentView = tableView

        tableView.allowsEmptySelection = false
        tableView.allowsMultipleSelection = false
        tableView.style = .inset
        tableView.dataSource = dataSource
        tableView.delegate = self

        configureColumns()
        setupTableViewMenu()
        reloadData()
    }

    // MARK: - Data

    func reloadData() {
        var items = loadItems()
        let searchText = searchField.stringValue
        items = filterItems(items, searchText: searchText)

        var snapshot = Snapshot()
        snapshot.appendSections([.main])
        snapshot.appendItems(items, toSection: .main)
        dataSource.apply(snapshot, animatingDifferences: true)
    }

    func itemForRow(_ row: Int) -> Item? {
        dataSource.itemIdentifier(forRow: row)
    }

    // MARK: - Configuration

    func applyBaseConfiguration(_ config: BaseConfiguration) {
        titleLabel.stringValue = config.title
        descriptionLabel.stringValue = config.description
        cancelButton.title = config.cancelButtonTitle
        confirmButton.title = config.confirmButtonTitle
        tableView.rowHeight = config.rowHeight
        tableView.intercellSpacing = config.cellSpacing
    }

    func addTableColumn(identifier: String, title: String, preferredWidth: CGFloat, minWidth: CGFloat? = nil, maxWidth: CGFloat? = nil, headerAlignment: NSTextAlignment? = nil) {
        let column = NSTableColumn(identifier: .init(identifier))
        column.title = title
        column.width = preferredWidth
        if let minWidth { column.minWidth = minWidth }
        if let maxWidth { column.maxWidth = maxWidth }
        if let headerAlignment { column.headerCell.alignment = headerAlignment }
        tableView.addTableColumn(column)
    }

    // MARK: - Actions

    @objc private func cancelAction() {
        didCancel()
    }

    @objc private func confirmAction() {
        guard tableView.selectedRow != NSNotFound,
              let item = dataSource.itemIdentifier(forRow: tableView.selectedRow) else { return }
        didConfirm(item: item)
    }

    @objc private func searchTextFieldDidChange(_ sender: NSSearchField) {
        reloadData()
    }

    // MARK: - Menu

    private func setupTableViewMenu() {
        let menu = NSMenu()
        menu.delegate = self
        tableView.menu = menu
    }

    // MARK: - DataSource

    private func makeDataSource() -> DataSource {
        DataSource(tableView: tableView) { [weak self] tableView, tableColumn, _, item in
            guard let self, let cellView = self.makeCellView(for: tableColumn, item: item) else { return NSView() }
            return cellView
        }
    }

    // MARK: - NSTableViewDelegate

    public func tableViewSelectionDidChange(_ notification: Notification) {
        let hasSelection = tableView.selectedRow != NSNotFound
        confirmButton.isEnabled = hasSelection
        if hasSelection, let item = dataSource.itemIdentifier(forRow: tableView.selectedRow) {
            didSelect(item: item)
        }
    }

    public func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        guard let item = dataSource.itemIdentifier(forRow: row) else { return true }
        return shouldSelect(item: item)
    }

    public func tableView(_ tableView: NSTableView, typeSelectStringFor tableColumn: NSTableColumn?, row: Int) -> String? {
        guard let item = dataSource.itemIdentifier(forRow: row) else { return nil }
        return typeSelectString(for: item)
    }

    deinit {
        print("\(Self.self) deinit")
    }
}

extension RunningItemPickerViewController: NSMenuDelegate {
    public func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let row = tableView.clickedRow
        guard row >= 0, let item = dataSource.itemIdentifier(forRow: row) else { return }
        for menuItem in contextMenuItems(for: item) {
            menu.addItem(menuItem)
        }
    }
}
```

**Step 2: Build**

```bash
swift build 2>&1 | xcsift
```

**Step 3: Commit**

```bash
git add Sources/RunningApplicationKit/RunningItemPickerViewController.swift
git commit -m "feat: Add RunningItemPickerViewController generic base class"
```

---

### Task 8: Refactor RunningApplicationPickerViewController to Inherit Base Class

Rewrite `RunningApplicationPickerViewController` to inherit from `RunningItemPickerViewController<RunningApplication>`.

**Files:**
- Modify: `Sources/RunningApplicationKit/RunningApplicationPickerViewController.swift` (full rewrite)

**Step 1: Rewrite RunningApplicationPickerViewController.swift**

```swift
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
                $0.string = "\(item.pid)"
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
        pasteboard.setString("\(item.pid)", forType: .string)
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
```

**Step 2: Build**

```bash
swift build 2>&1 | xcsift
```

**Step 3: Commit**

```bash
git add Sources/RunningApplicationKit/RunningApplicationPickerViewController.swift
git commit -m "refactor: Rewrite RunningApplicationPickerViewController to inherit base class"
```

---

### Task 9: Create RunningProcessPickerViewController

**Files:**
- Create: `Sources/RunningApplicationKit/RunningProcessPickerViewController.swift`

**Step 1: Create RunningProcessPickerViewController.swift**

```swift
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
                $0.string = "\(item.pid)"
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
        pasteboard.setString("\(item.pid)", forType: .string)
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
```

**Step 2: Build**

```bash
swift build 2>&1 | xcsift
```

**Step 3: Commit**

```bash
git add Sources/RunningApplicationKit/RunningProcessPickerViewController.swift
git commit -m "feat: Add RunningProcessPickerViewController"
```

---

### Task 10: Create RunningPickerTabViewController

**Files:**
- Create: `Sources/RunningApplicationKit/RunningPickerTabViewController.swift`

**Step 1: Create RunningPickerTabViewController.swift**

```swift
import AppKit

public final class RunningPickerTabViewController: NSTabViewController {
    public let applicationPickerViewController: RunningApplicationPickerViewController
    public let processPickerViewController: RunningProcessPickerViewController

    public init(
        applicationConfiguration: RunningApplicationPickerViewController.Configuration = .init(),
        processConfiguration: RunningProcessPickerViewController.Configuration = .init()
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

        let appTabItem = NSTabViewItem(viewController: applicationPickerViewController)
        appTabItem.label = "Applications"

        let processTabItem = NSTabViewItem(viewController: processPickerViewController)
        processTabItem.label = "Processes"

        addTabViewItem(appTabItem)
        addTabViewItem(processTabItem)
    }
}

import SwiftUI

@available(macOS 14.0, *)
#Preview(traits: .fixedLayout(width: 800, height: 700)) {
    RunningPickerTabViewController()
}
```

**Step 2: Build**

```bash
swift build 2>&1 | xcsift
```

**Step 3: Commit**

```bash
git add Sources/RunningApplicationKit/RunningPickerTabViewController.swift
git commit -m "feat: Add RunningPickerTabViewController with Applications and Processes tabs"
```

---

### Task 11: Update Package.swift and CLAUDE.md

**Files:**
- Modify: `Package.swift` (no changes needed — single target, all .swift files auto-included)
- Modify: `CLAUDE.md` (update architecture description)

**Step 1: Update CLAUDE.md architecture section**

Update the Architecture section to reflect the new components.

**Step 2: Final build verification**

```bash
swift package update && swift build 2>&1 | xcsift
```

**Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: Update CLAUDE.md with process support architecture"
```
