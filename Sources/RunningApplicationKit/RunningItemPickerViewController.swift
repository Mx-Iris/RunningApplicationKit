import AppKit

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

        configureColumns()
        setupTableViewMenu()
        reloadData()
    }

    // MARK: - Data

    func reloadData() {
        cachedItems = loadItems()
        applyFilter()
    }

    func updateItems(_ items: [Item], animatingDifferences: Bool = false) {
        cachedItems = items
        applyFilter(animatingDifferences: animatingDifferences)
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
        if !title.isEmpty {
            column.sortDescriptorPrototype = NSSortDescriptor(key: identifier, ascending: true)
        }
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
        let hasSelection = tableView.selectedRow != NSNotFound
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
