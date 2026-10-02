import AppKit
import Testing
@testable import RunningApplicationKit

/// A picker filled from a ``RunningItemSource`` instead of from this machine, and the two
/// rules that go with it: a row that cannot be picked has to *look* unpickable, and
/// pid 0 / pid 1 are never pickable.
///
/// Nothing here reads a real process. The supplied source is the whole point — it is what
/// lets the list be exactly the rows a test wants, which the local process table could
/// never be.
@Suite("Supplied item source")
@MainActor
struct SuppliedItemSourceTests {
    // MARK: - Fixtures

    static func process(_ processIdentifier: pid_t, _ name: String) -> RunningProcess {
        RunningProcess(processIdentifier: processIdentifier, name: name, executablePath: "/usr/bin/\(name)")
    }

    /// Records what it was asked for, so a test can tell one fetch from two.
    final class CountingSource: @unchecked Sendable {
        private(set) var loadCount = 0
        private let items: [RunningProcess]
        private let failure: (any Error)?

        init(items: [RunningProcess], failure: (any Error)? = nil) {
            self.items = items
            self.failure = failure
        }

        func makeItemSource() -> AnyRunningItemSource<RunningProcess> {
            AnyRunningItemSource { [self] in
                loadCount += 1
                if let failure { throw failure }
                return items
            }
        }
    }

    struct SourceFailure: Error {}

    final class RecordingDelegate: RunningProcessPickerViewController.Delegate {
        var selectableProcessIdentifiers: Set<pid_t>?
        private(set) var failures: [any Error] = []

        func runningProcessPickerViewController(
            _ viewController: RunningProcessPickerViewController,
            shouldSelectProcess process: RunningProcess,
        ) -> Bool {
            guard let selectableProcessIdentifiers else { return true }
            return selectableProcessIdentifiers.contains(process.processIdentifier)
        }

        func runningProcessPickerViewController(
            _ viewController: RunningProcessPickerViewController,
            didFailToLoadProcesses error: any Error,
        ) {
            failures.append(error)
        }
    }

    /// Loads a source-backed picker in a real window and runs the fetch to completion.
    ///
    /// The window is not incidental — see the note in `PickerStructureTests`. The fetch is
    /// awaited rather than slept on: it is a task of the picker's own, and `reload()` is
    /// what starts it without waiting for the view to appear.
    static func loadedPicker(
        source: CountingSource,
        delegate: RecordingDelegate? = nil,
    ) async -> (picker: RunningProcessPickerViewController, window: NSWindow) {
        let picker = RunningProcessPickerViewController(
            itemSource: source.makeItemSource(),
            configuration: .init(style: .list),
        )
        picker.delegate = delegate
        let window = NSWindow(
            contentRect: .init(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false,
        )
        window.contentViewController = picker
        window.layoutIfNeeded()
        picker.view.layoutSubtreeIfNeeded()
        picker.reload()
        await picker.pendingSourceLoad?.value
        return (picker, window)
    }

    // MARK: - The list comes from the source

    @Test("Shows exactly the supplied items")
    func showsSuppliedItems() async {
        let source = CountingSource(items: [
            Self.process(4242, "someone-elses-daemon"),
            Self.process(4243, "another-one"),
        ])
        let (picker, window) = await Self.loadedPicker(source: source)
        defer { withExtendedLifetime(window) {} }

        #expect(picker.tableView.numberOfRows == 2)
        #expect(source.loadCount == 1)
    }

    /// The local process table has hundreds of entries and always contains this test
    /// runner, so "the supplied list and nothing else" is checkable without naming any
    /// real process: our own pid must not be in it.
    @Test("Never mixes in this machine's processes")
    func doesNotEnumerateLocally() async {
        let source = CountingSource(items: [Self.process(4242, "someone-elses-daemon")])
        let (picker, window) = await Self.loadedPicker(source: source)
        defer { withExtendedLifetime(window) {} }

        #expect(picker.tableView.numberOfRows == 1)
        let shownProcessIdentifiers = picker.itemsForTesting.map(\.processIdentifier)
        #expect(shownProcessIdentifiers == [4242])
        #expect(!shownProcessIdentifiers.contains(getpid()))
    }

    @Test("Fetches again on reload, and not before")
    func reloadFetchesAgain() async {
        let source = CountingSource(items: [Self.process(4242, "someone-elses-daemon")])
        let (picker, window) = await Self.loadedPicker(source: source)
        defer { withExtendedLifetime(window) {} }
        #expect(source.loadCount == 1)

        picker.reload()
        await picker.pendingSourceLoad?.value
        #expect(source.loadCount == 2)
    }

    // MARK: - Failure

    /// A fetch that threw and a machine with nothing to list would otherwise be the same
    /// empty table. The delegate is how the caller tells them apart.
    @Test("Reports a failed fetch and stops showing placeholders")
    func failureIsReportedAndClearsTheSkeleton() async {
        let delegate = RecordingDelegate()
        let source = CountingSource(items: [], failure: SourceFailure())
        let (picker, window) = await Self.loadedPicker(source: source, delegate: delegate)
        defer { withExtendedLifetime(window) {} }

        #expect(delegate.failures.count == 1)
        #expect(picker.isSkeletonVisible == false)
        #expect(picker.tableView.numberOfRows == 0)
    }

    /// The base class only hides the skeleton on the first *non-empty* batch, so an empty
    /// answer used to leave placeholder rows pulsing forever.
    @Test("Stops showing placeholders when the answer is legitimately empty")
    func emptyAnswerClearsTheSkeleton() async {
        let source = CountingSource(items: [])
        let (picker, window) = await Self.loadedPicker(source: source)
        defer { withExtendedLifetime(window) {} }

        #expect(picker.isSkeletonVisible == false)
        #expect(picker.tableView.numberOfRows == 0)
    }

    // MARK: - Shown but not selectable

    static func rowOpacity(_ picker: RunningProcessPickerViewController, row: Int) -> CGFloat {
        // A fresh row view rather than the table's own: this asserts the wiring from row
        // index to item to opacity, without depending on when AppKit decides to
        // materialise a row view.
        let rowView = NSTableRowView()
        picker.tableView(picker.tableView, didAdd: rowView, forRow: row)
        return rowView.alphaValue
    }

    @Test("launchd is listed, dimmed, and cannot be picked")
    func restrictedProcessIsDimmedAndUnselectable() async {
        let source = CountingSource(items: [Self.process(1, "launchd")])
        let (picker, window) = await Self.loadedPicker(source: source)
        defer { withExtendedLifetime(window) {} }

        #expect(picker.tableView.numberOfRows == 1, "it must be shown, not filtered out")
        #expect(picker.tableView(picker.tableView, shouldSelectRow: 0) == false)
        #expect(Self.rowOpacity(picker, row: 0) == RunningProcessPickerViewController.unselectableRowOpacity)
    }

    @Test("An ordinary process is fully opaque and can be picked")
    func ordinaryProcessIsSelectable() async {
        let source = CountingSource(items: [Self.process(4242, "someone-elses-daemon")])
        let (picker, window) = await Self.loadedPicker(source: source)
        defer { withExtendedLifetime(window) {} }

        #expect(picker.tableView(picker.tableView, shouldSelectRow: 0) == true)
        #expect(Self.rowOpacity(picker, row: 0) == 1)
    }

    /// The caller's own refusal — "this one is a different uid, you cannot inject it" —
    /// reaches the same two places as the library's rule.
    @Test("A delegate refusal dims the row too")
    func delegateRefusalDimsTheRow() async {
        let delegate = RecordingDelegate()
        delegate.selectableProcessIdentifiers = []
        let source = CountingSource(items: [Self.process(4242, "someone-elses-daemon")])
        let (picker, window) = await Self.loadedPicker(source: source, delegate: delegate)
        defer { withExtendedLifetime(window) {} }

        #expect(picker.tableView(picker.tableView, shouldSelectRow: 0) == false)
        #expect(Self.rowOpacity(picker, row: 0) == RunningProcessPickerViewController.unselectableRowOpacity)
    }

    @Test("The restricted rule is by identifier, so a renamed pid 1 is still refused")
    func restrictionIsByIdentifier() {
        #expect(RestrictedProcess.isRestricted(processIdentifier: 0))
        #expect(RestrictedProcess.isRestricted(processIdentifier: 1))
        #expect(!RestrictedProcess.isRestricted(processIdentifier: 2))
        #expect(!RestrictedProcess.isRestricted(processIdentifier: 4242))
    }

    // MARK: - One tab

    @Test("A single configured tab is hosted directly, with no tab control")
    func singleTabIsHostedDirectly() {
        let source = CountingSource(items: [])
        let picker = RunningPickerTabViewController(
            configuration: .init(tabs: [.processes]),
            processItemSource: source.makeItemSource(),
        )
        let window = NSWindow(
            contentRect: .init(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled],
            backing: .buffered,
            defer: false,
        )
        window.contentViewController = picker
        window.layoutIfNeeded()
        defer { withExtendedLifetime(window) {} }

        #expect(picker.children.count == 1)
        #expect(picker.children.first is RunningProcessPickerViewController)
        #expect(!(picker.children.first is NSTabViewController))
    }

    @Test("Both tabs still go through a tab controller")
    func twoTabsKeepTheTabController() {
        let picker = RunningPickerTabViewController()
        let window = NSWindow(
            contentRect: .init(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled],
            backing: .buffered,
            defer: false,
        )
        window.contentViewController = picker
        window.layoutIfNeeded()
        defer { withExtendedLifetime(window) {} }

        #expect(picker.children.first is NSTabViewController)
    }

    /// Prefetching a list the caller did not ask for is a wasted round trip to another
    /// machine, not just wasted local work.
    @Test("A tab that is not configured is never fetched")
    func unconfiguredTabIsNotFetched() {
        let source = CountingSource(items: [])
        let picker = RunningPickerTabViewController(
            configuration: .init(tabs: [.applications]),
            processItemSource: source.makeItemSource(),
        )
        let window = NSWindow(
            contentRect: .init(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled],
            backing: .buffered,
            defer: false,
        )
        window.contentViewController = picker
        window.layoutIfNeeded()
        defer { withExtendedLifetime(window) {} }

        #expect(source.loadCount == 0)
    }

    @Test("An empty tab list falls back to both rather than to nothing")
    func emptyTabListFallsBack() {
        #expect(RunningPickerTabViewController.Configuration(tabs: []).tabs == RunningPickerTabViewController.Tab.allCases)
    }
}
