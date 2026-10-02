/// Where a picker's items come from, when they do not come from this machine.
///
/// The library's own pickers enumerate the local machine directly and do not go through
/// this protocol — see ``RunningProcessPickerViewController/init(itemSource:configuration:)``
/// for the distinction. Supplying a source is how a caller shows items the library has no
/// way to see: the processes running on another machine, most usefully.
///
/// `loadItems()` is a complete snapshot rather than a stream of changes, because that is
/// what a caller fetching across a process or machine boundary can produce without
/// inventing a change feed. The local pickers keep their incremental refresh precisely
/// because they *can* do better than a snapshot.
public protocol RunningItemSource<Item>: Sendable {
    associatedtype Item: RunningItem

    /// One complete snapshot of the items to offer.
    func loadItems() async throws -> [Item]
}

/// A ``RunningItemSource`` with its concrete type erased, and the type the pickers
/// actually store.
///
/// A concrete generic struct rather than `any RunningItemSource<Item>`: this library
/// deploys to macOS 11, and the runtime support for an existential with a constrained
/// associated type starts at macOS 13. Measured — not a style preference.
///
/// The closure initializer is usually the one a caller wants. Fetching a list from
/// somewhere else is rarely a type worth naming.
public struct AnyRunningItemSource<Item: RunningItem>: RunningItemSource {
    private let load: @Sendable () async throws -> [Item]

    public init(_ load: @escaping @Sendable () async throws -> [Item]) {
        self.load = load
    }

    public init<Source: RunningItemSource>(_ source: Source) where Source.Item == Item {
        self.load = { try await source.loadItems() }
    }

    public func loadItems() async throws -> [Item] {
        try await load()
    }
}
