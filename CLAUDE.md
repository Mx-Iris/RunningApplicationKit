# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Test

Pure Swift Package Manager library. No Xcode project. One dependency: [swift-proc](https://github.com/Mx-Iris/swift-proc), the libproc wrapper by the same author, which answers every process query.

```bash
swift package update && swift build 2>&1 | xcsift
swift test 2>&1 | xcsift
```

Tests (`Tests/RunningApplicationKitTests/`) are deterministic and environment-independent —
nothing reads a real process, a real binary, or anything about the machine running them —
with one exception, `LocalProcessTests`, described after the list:

- Kernel value mapping: CPU type and subtype to `Architecture` (capability bits ignored),
  the kernel's platform value to `Platform` (`0` is `nil`).
- Configuration: style defaults, explicit overrides, and what reaches `BaseConfiguration`.
- List row layout and picker structure: the two places outside pure functions. Four
  layout/wiring bugs reached screenshots while compiling cleanly and passing every other
  test — a style ignored at initialisation, a table column stuck at its 100pt default, a
  text column that collapsed instead of filling the row, and an empty stack view left
  visible. Rows are sized by constraints and pickers are hosted in a real `NSWindow`,
  because frame-assigned views pick up autoresizing that hides exactly these faults.

- Supplied item source: the list comes from the caller and never from this machine, reload
  re-fetches, a failed or empty answer clears the skeleton, and the shown-but-not-selectable
  rules. A test double supplies the rows, which is what makes a one-row list — `launchd` and
  nothing else — expressible at all; the local process table never could be.

`LocalProcessTests` reads real processes: the test process itself, Finder, and children it
starts. The name observer test copies `/bin/sleep` under a file name longer than 31 bytes,
so the kernel's name (cut to 31 bytes) and the file name differ and each is matched by its
own observer. A symbolic link would not do: the kernel names a process after the file the
link resolves to. Children are killed with `SIGKILL`, which the test runner cannot have
blocked. The `.pid` observer test needs macOS 15, where the exit is reported by the kernel.

The picker's higher-level behaviour has no tests, and local enumeration is covered only for
the test process itself.

**xcsift reports failing swift-testing tests as a success** — judge test outcomes by the raw
exit code of `swift test`, never by the xcsift summary.

An Example app lives in `Example/` with its own `.xcodeproj` (depends on the library via local path).

## Key Constraints

- **Swift 6 strict concurrency** (`swift-tools-version: 6.2`, `swiftLanguageModes: [.v6]`). All new code must satisfy `Sendable` checking and actor isolation rules.
- **macOS 12+ deployment target** — swift-proc's floor, and the lowest target Xcode 27's macOS SDK accepts — but some code gates on newer OS versions (e.g., `NSSearchField.controlSize = .extraLarge` on macOS 26+, the `.pid` observer's exit notification on macOS 15+).

## Architecture

RunningApplicationKit provides data models, observers, and picker UI for macOS running applications and BSD processes.

### Public API Boundary

Only `RunningPickerTabViewController` (and its configuration/delegate/column/tab types), `RunningApplication`, `RunningProcess`, `RunningProcessEnumerator`, `RunningItem`, `RunningItemSource` / `AnyRunningItemSource`, `RestrictedProcess`, `Architecture`, and the two observer actors are `public`. The individual picker view controllers (`RunningApplicationPickerViewController`, `RunningProcessPickerViewController`) and the base class `RunningItemPickerViewController` are `internal` — consumers interact through the tab VC.

**Keep them internal.** Making a picker public was tried while adding the supplied-source feature and withdrawn: Swift requires every `override` in a public class to be public too, which would have published the forty-odd subclass hooks, `BaseConfiguration` and `PickerField` — and worse, made `didConfirm(item:)` and `loadItems()` *callable* from outside, firing delegate callbacks behind the picker's back. Anything a consumer needs goes on the tab VC. See `Documentations/Evolutions/0003-injected-item-source.md`.

### Supplying the list

`RunningPickerTabViewController(processItemSource:)` fills the Processes list from the caller instead of from this machine, and `Configuration.tabs` picks which lists to show — a single entry drops the tab bar and hosts that list directly. Two deliberate differences from the local list, both in `RunningProcessPickerViewController`:

- **No polling.** `loadItems()` may be a round trip to another machine, so it runs once when the picker appears; re-fetching is `reloadProcesses()`, on the caller's schedule. A tab that is not configured is never prefetched, for the same reason.
- **An empty or failed answer clears the skeleton explicitly.** The base class only hides placeholders on the first *non-empty* batch, so without that the rows would pulse forever. A failure also reaches `didFailToLoadProcesses` — otherwise a failed fetch and a machine with nothing to list are the same empty table.

`RunningItemSource` has a primary associated type but the pickers store `AnyRunningItemSource` rather than `any RunningItemSource<Item>`: the runtime support for a parameterised existential starts at macOS 13 and this library deploys to 12.

### Shown but not selectable

`RunningItemPickerViewController.isSelectable(_:)` is the single answer behind both halves: `tableView(_:shouldSelectRow:)` refuses the row, and `tableView(_:didAdd:forRow:)` drops its `alphaValue` to `unselectableRowOpacity`. Before that second half existed, `shouldSelect(item:)` returning `false` left the row looking perfectly pickable, so the refusal read as the list being broken. It is done per row view, not in the cell-building closure, which runs once per *column* in the table style.

`RestrictedProcess` — pid 0 and pid 1 — is refused ahead of the delegate, unconditionally and by identifier rather than by name.

### Concurrency Model

- **Observers** (`RunningApplicationObserver`, `RunningProcessObserver`) are Swift `actor` types. `RunningApplicationObserver` uses KVO; `RunningProcessObserver` uses async `Task`-based polling, except that on macOS 15+ a `.pid` target waits for the kernel's exit notification (swift-proc's `waitForTermination()`) while the process runs.
- **Picker VCs** are `@MainActor` (implicit via `NSViewController`). `RunningProcessPickerViewController` offloads process enumeration to a background `DispatchQueue` and bounces results back to main.
- **`RunningProcessEnumerator`** keeps its icon and sandbox caches in `ThreadSafeCache`, a dictionary behind an `NSLock`. Architecture and platform are not cached: each is one system call per process.

### Low-Level System APIs

`BSDProcess` (internal) answers every process query, through swift-proc's `ProcessInformation` and `ProcessInformationPrivate` modules — understanding these is important when debugging or extending process-related features:

- `ProcessIdentifier.list()` / `executablePath()` — enumeration and paths. The kernel gives out
  a path for any process.
- `name()` (`proc_name`) — the kernel's name for a process: the executable's file name cut to
  31 bytes, after symbolic links are resolved. Same-user only, unless the caller is root.
  `proc_name` needs a buffer of at least 32 bytes; this library once passed 17, so no name was
  ever read and `.name` observers never matched.
- `architecture()` (`PROC_PIDARCHINFO`) — the architecture the kernel actually runs the process
  as, which is what distinguishes arm64 from arm64e. Same-user only.
- `platform()` (`PROC_PIDPLATFORMINFO`, a flavor the SDK does not declare) — the platform of the
  executable slice the kernel loaded, which is how simulator processes are identified: they run
  as plain `arm64`, like host processes. Any caller may ask about any process. Proposal 0001
  concluded the kernel had no such query and parsed Mach-O headers instead; that was wrong, and
  the parser is gone. See `Documentations/Internal/PlatformDetection.md`.
- `waitForTermination()` — kqueue `NOTE_EXIT`, behind `.pid` observers on macOS 15+.
- `kill(pid, 0)` — whether a process still exists.
- Security framework `SecCode` APIs — sandbox detection through the `com.apple.security.app-sandbox`
  entitlement.

### UI Inheritance Chain

`RunningItemPickerViewController<Item: RunningItem>` is a generic base class providing: search field, `NSTableViewDiffableDataSource`, column sorting, context menus, cancel/confirm buttons. Subclasses override hooks (`loadItems()`, `configureColumns()`, `makeCellView(for:item:)`, `compareItems(_:_:columnIdentifier:)`, etc.).

Cell views in `TableCellViews.swift` use distinct subclasses per column type (e.g., `NameTableCellView`, `PIDTableCellView`) — this enables `NSTableView` cell reuse by class identity via the `NSTableView.makeView(ofClass:modify:)` extension.
