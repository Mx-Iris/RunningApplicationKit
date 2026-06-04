import AppKit

protocol PickerColumn: RawRepresentable where RawValue == String {
    var title: String { get }
    var preferredWidth: CGFloat { get }
    var minWidth: CGFloat? { get }
    var maxWidth: CGFloat? { get }
    var headerAlignment: NSTextAlignment? { get }
}

struct BaseConfiguration {
    var title: String
    var description: String
    var cancelButtonTitle: String
    var confirmButtonTitle: String
    var rowHeight: CGFloat
    var cellSpacing: CGSize

    init(
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

class RunningItemPickerViewController<Item: RunningItem>: NSViewController, NSTableViewDelegate, NSMenuDelegate {
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
    private var cachedItems: [Item] = []
    private var sortColumnIdentifier: String?
    private var sortAscending: Bool = true

    private let skeletonView = SkeletonListView()
    private var hasShownInitialData = false
    private var skeletonOverlayIsVisible = false

    // MARK: - Subclass Hooks

    /// Return the items to display. Called on each reload.
    func loadItems() -> [Item] { [] }

    /// Filter items based on search text. Default implementation filters by name.
    func filterItems(_ items: [Item], searchText: String) -> [Item] {
        guard !searchText.isEmpty else { return items }
        return items.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    /// Configure the table columns. Subclasses must call `addTableColumn` for each column.
    func configureColumns() {}

    /// Return a cell view for the given column and item.
    func makeCellView(for tableColumn: NSTableColumn, item: Item) -> NSView? { nil }

    /// Return context menu items for the given item.
    func contextMenuItems(for item: Item) -> [NSMenuItem] { [] }

    /// Called when the user clicks Cancel.
    func didCancel() {}

    /// Called when the user confirms selection.
    func didConfirm(item: Item) {}

    /// Called when selection changes.
    func didSelect(item: Item) {}

    /// Return whether the given item should be selectable.
    func shouldSelect(item: Item) -> Bool { true }

    /// Return the type-select string for the given item. Default returns name.
    func typeSelectString(for item: Item) -> String? { item.name }

    /// Compare two items for sorting by the given column. Return `.orderedSame` for non-sortable columns.
    func compareItems(_ lhs: Item, _ rhs: Item, columnIdentifier: String) -> ComparisonResult { .orderedSame }

    // MARK: - Lifecycle

    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.addSubview(scrollView)
        view.addSubview(topStackView)
        view.addSubview(bottomStackView)
        view.addSubview(skeletonView)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.scrollerStyle = .overlay
        topStackView.translatesAutoresizingMaskIntoConstraints = false
        bottomStackView.translatesAutoresizingMaskIntoConstraints = false
        skeletonView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            topStackView.topAnchor.constraint(equalTo: view.topAnchor, constant: 0),
            topStackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 0),
            topStackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: 0),

            scrollView.topAnchor.constraint(equalTo: topStackView.bottomAnchor, constant: 20),
            scrollView.bottomAnchor.constraint(equalTo: bottomStackView.topAnchor, constant: -20),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 0),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: 0),

            bottomStackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 0),
            bottomStackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: 0),
            bottomStackView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: 0),

            // Anchor the skeleton to the scroll view's clip view so the column
            // header stays visible above it and the skeleton doesn't scroll.
            skeletonView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            skeletonView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            skeletonView.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            skeletonView.bottomAnchor.constraint(equalTo: scrollView.contentView.bottomAnchor),

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
        searchField.refusesFirstResponder = true
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

        skeletonView.tableView = tableView

        configureColumns()
        setupTableViewMenu()
        reloadData()

        if cachedItems.isEmpty {
            skeletonView.isHidden = false
            skeletonOverlayIsVisible = true
        } else {
            hasShownInitialData = true
            skeletonView.isHidden = true
            skeletonOverlayIsVisible = false
        }
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        if skeletonOverlayIsVisible {
            skeletonView.startAnimating()
        }
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        skeletonView.stopAnimating()
    }

    // MARK: - Data

    func reloadData() {
        cachedItems = loadItems()
        applyFilter()
    }

    func updateItems(_ items: [Item], animatingDifferences: Bool = false) {
        cachedItems = items
        applyFilter(animatingDifferences: animatingDifferences)
        if !hasShownInitialData, !items.isEmpty {
            hasShownInitialData = true
            skeletonOverlayIsVisible = false
            hideSkeletonAnimated()
        }
    }

    /// Whether the loading skeleton overlay is currently visible.
    var isSkeletonOverlayVisible: Bool { skeletonOverlayIsVisible }

    /// Tunable appearance for the loading skeleton overlay.
    var skeletonAppearance: SkeletonAppearance {
        get { skeletonView.skeletonAppearance }
        set { skeletonView.skeletonAppearance = newValue }
    }

    /// Manually show or hide the skeleton overlay. Once called, the natural
    /// "hide on first data" path is suppressed so the caller owns visibility.
    /// - Parameters:
    ///   - visible: target visibility.
    ///   - alpha: target alpha when `visible == true`, clamped to [0, 1].
    ///     Use a value below 1 to let the underlying content show through.
    ///   - animated: when hiding, fade out; when showing, fade alpha in.
    func setSkeletonOverlayVisible(_ visible: Bool, alpha: CGFloat = 1, animated: Bool = true) {
        skeletonOverlayIsVisible = visible
        hasShownInitialData = true

        // Cancel any in-flight fade so a rapid toggle doesn't leave the
        // overlay stuck mid-animation.
        skeletonView.layer?.removeAllAnimations()

        if visible {
            let clampedAlpha = max(0, min(1, alpha))
            skeletonView.isHidden = false
            skeletonView.startAnimating()
            if animated {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.18
                    context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    skeletonView.animator().alphaValue = clampedAlpha
                }
            } else {
                skeletonView.alphaValue = clampedAlpha
            }
        } else if animated {
            hideSkeletonAnimated()
        } else {
            skeletonView.stopAnimating()
            skeletonView.isHidden = true
            skeletonView.alphaValue = 1
        }
    }

    private func hideSkeletonAnimated() {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            skeletonView.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            // NSAnimationContext completion fires on the main thread, but the
            // closure type is @Sendable under Swift 6, so reassert isolation.
            MainActor.assumeIsolated {
                guard let self else { return }
                // If the user toggled the overlay back on during the fade, the
                // intent is now "visible" — skip cleanup so we don't hide it.
                guard !self.skeletonOverlayIsVisible else { return }
                self.skeletonView.stopAnimating()
                self.skeletonView.isHidden = true
                self.skeletonView.alphaValue = 1
            }
        })
    }

    func applyFilter(animatingDifferences: Bool = true) {
        let searchText = searchField.stringValue
        var items = filterItems(cachedItems, searchText: searchText)

        if let sortColumnIdentifier {
            let ascending = sortAscending
            items.sort { lhs, rhs in
                let result = compareItems(lhs, rhs, columnIdentifier: sortColumnIdentifier)
                return ascending ? result == .orderedAscending : result == .orderedDescending
            }
        }

        // Preserve selection across snapshot updates
        let selectedItem = tableView.selectedRow >= 0 ? dataSource.itemIdentifier(forRow: tableView.selectedRow) : nil

        var snapshot = Snapshot()
        snapshot.appendSections([.main])
        snapshot.appendItems(items, toSection: .main)
        dataSource.apply(snapshot, animatingDifferences: animatingDifferences)

        if let selectedItem, let row = dataSource.row(forItemIdentifier: selectedItem), row >= 0 {
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
    }

    // MARK: - Configuration

    func applyBaseConfiguration(_ config: BaseConfiguration) {
        titleLabel.stringValue = config.title
        descriptionLabel.stringValue = config.description
        cancelButton.title = config.cancelButtonTitle
        confirmButton.title = config.confirmButtonTitle
        tableView.rowHeight = config.rowHeight
        tableView.intercellSpacing = config.cellSpacing
        skeletonView.rowHeight = config.rowHeight
        skeletonView.rowSpacing = config.cellSpacing.height
    }

    func configureColumns<Column: PickerColumn>(_ columns: [Column]) {
        for column in columns {
            addTableColumn(
                identifier: column.rawValue,
                title: column.title,
                preferredWidth: column.preferredWidth,
                minWidth: column.minWidth,
                maxWidth: column.maxWidth,
                headerAlignment: column.headerAlignment
            )
        }
        let iconStyleIdentifiers: Set<String> = ["icon", "sandboxed"]
        skeletonView.columns = columns.map { column in
            SkeletonColumnDescriptor(
                identifier: column.rawValue,
                style: iconStyleIdentifiers.contains(column.rawValue) ? .icon : .text,
                alignment: column.headerAlignment ?? .left
            )
        }
    }

    func addTableColumn(identifier: String, title: String, preferredWidth: CGFloat, minWidth: CGFloat? = nil, maxWidth: CGFloat? = nil, headerAlignment: NSTextAlignment? = nil) {
        let column = NSTableColumn(identifier: .init(identifier))
        column.title = title
        column.width = preferredWidth
        if let minWidth { column.minWidth = minWidth }
        if let maxWidth { column.maxWidth = maxWidth }
        if let headerAlignment { column.headerCell.alignment = headerAlignment }
        if !title.isEmpty {
            column.sortDescriptorPrototype = NSSortDescriptor(key: identifier, ascending: true)
        }
        tableView.addTableColumn(column)
    }

    // MARK: - Shared Cell Helpers

    /// Create a cell view for common column types shared across all picker VCs.
    /// Returns nil if the column identifier is not a shared type.
    func makeSharedCellView(columnIdentifier: String, item: Item) -> NSView? {
        switch columnIdentifier {
        case "icon":
            return tableView.makeView(ofClass: IconTableCellView.self) {
                $0.image = item.icon
            }
        case "name":
            return tableView.makeView(ofClass: NameTableCellView.self) {
                $0.string = item.name
            }
        case "pid":
            return tableView.makeView(ofClass: PIDTableCellView.self) {
                $0.string = "\(item.processIdentifier)"
            }
        case "architecture":
            return tableView.makeView(ofClass: ArchitectureTableCellView.self) {
                $0.string = item.architecture?.description
            }
        default:
            return nil
        }
    }

    func makeSandboxedCellView(isSandboxed: Bool, isLoading: Bool = false) -> NSView {
        tableView.makeView(ofClass: StatusIconTableCellView.self) {
            if isLoading {
                $0.isLoading = true
            } else {
                $0.isLoading = false
                $0.image = isSandboxed ? .checkmarkImage : .xmarkImage
                $0.tintColor = isSandboxed ? .systemGreen : .systemRed
            }
        }
    }

    // MARK: - Shared Comparison Helpers

    /// Compare two items by a common column identifier shared across all picker VCs.
    /// Returns nil if the column identifier is not a shared type.
    func compareSharedItems(_ lhs: Item, _ rhs: Item, columnIdentifier: String) -> ComparisonResult? {
        switch columnIdentifier {
        case "icon":
            return .orderedSame
        case "name":
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name)
        case "pid":
            return compareNumericValues(lhs.processIdentifier, rhs.processIdentifier)
        case "architecture":
            return (lhs.architecture?.description ?? "").compare(rhs.architecture?.description ?? "")
        case "sandboxed":
            return compareBooleanValues(lhs.isSandboxed, rhs.isSandboxed)
        default:
            return nil
        }
    }

    func compareNumericValues<T: Comparable>(_ lhs: T, _ rhs: T) -> ComparisonResult {
        if lhs == rhs { return .orderedSame }
        return lhs < rhs ? .orderedAscending : .orderedDescending
    }

    func compareBooleanValues(_ lhs: Bool, _ rhs: Bool) -> ComparisonResult {
        if lhs == rhs { return .orderedSame }
        return lhs ? .orderedAscending : .orderedDescending
    }

    // MARK: - Shared Context Menu Helpers

    func makeCopyPIDMenuItem(for item: Item) -> NSMenuItem {
        let menuItem = NSMenuItem(title: "Copy PID", action: #selector(copyPIDAction(_:)), keyEquivalent: "")
        menuItem.target = self
        menuItem.representedObject = item
        return menuItem
    }

    @objc private func copyPIDAction(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? Item else { return }
        copyToPasteboard("\(item.processIdentifier)")
    }

    // MARK: - Actions

    @objc private func cancelAction() {
        didCancel()
    }

    @objc private func confirmAction() {
        guard tableView.selectedRow >= 0,
              let item = dataSource.itemIdentifier(forRow: tableView.selectedRow) else { return }
        didConfirm(item: item)
    }

    @objc private func searchTextFieldDidChange(_ sender: NSSearchField) {
        applyFilter()
    }

    func copyToPasteboard(_ string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
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

    func tableViewSelectionDidChange(_ notification: Notification) {
        let hasSelection = tableView.selectedRow >= 0
        confirmButton.isEnabled = hasSelection
        if hasSelection, let item = dataSource.itemIdentifier(forRow: tableView.selectedRow) {
            didSelect(item: item)
        }
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        guard let item = dataSource.itemIdentifier(forRow: row) else { return true }
        return shouldSelect(item: item)
    }

    func tableView(_ tableView: NSTableView, typeSelectStringFor tableColumn: NSTableColumn?, row: Int) -> String? {
        guard let item = dataSource.itemIdentifier(forRow: row) else { return nil }
        return typeSelectString(for: item)
    }

    func tableView(_ tableView: NSTableView, didClick tableColumn: NSTableColumn) {
        guard tableColumn.sortDescriptorPrototype != nil else { return }
        let columnIdentifier = tableColumn.identifier.rawValue

        if sortColumnIdentifier == columnIdentifier {
            if sortAscending {
                sortAscending = false
            } else {
                sortColumnIdentifier = nil
            }
        } else {
            sortColumnIdentifier = columnIdentifier
            sortAscending = true
        }

        if let sortColumnIdentifier {
            tableView.sortDescriptors = [NSSortDescriptor(key: sortColumnIdentifier, ascending: sortAscending)]
        } else {
            tableView.sortDescriptors = []
        }

        applyFilter(animatingDifferences: false)
    }

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let row = tableView.clickedRow
        guard row >= 0, let item = dataSource.itemIdentifier(forRow: row) else { return }
        for menuItem in contextMenuItems(for: item) {
            menu.addItem(menuItem)
        }
    }

    deinit {
        #if DEBUG
        print("\(Self.self) deinit")
        #endif
    }
}
