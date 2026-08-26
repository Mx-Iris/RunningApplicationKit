# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Test

Pure Swift Package Manager library. No Xcode project, no external dependencies.

```bash
swift package update && swift build 2>&1 | xcsift
swift test 2>&1 | xcsift
```

Tests (`Tests/RunningApplicationKitTests/`) are deterministic and environment-independent —
nothing reads a real process, a real binary, or anything about the machine running them:

- Mach-O parsing: byte order, fat slice selection, load command bounds, driven by
  hand-built byte arrays.
- Configuration: style defaults, explicit overrides, and what reaches `BaseConfiguration`.
- List row layout and picker structure: the two places outside pure functions. Four
  layout/wiring bugs reached screenshots while compiling cleanly and passing every other
  test — a style ignored at initialisation, a table column stuck at its 100pt default, a
  text column that collapsed instead of filling the row, and an empty stack view left
  visible. Rows are sized by constraints and pickers are hosted in a real `NSWindow`,
  because frame-assigned views pick up autoresizing that hides exactly these faults.

Process enumeration and the picker's higher-level behaviour have no tests.

**xcsift reports failing swift-testing tests as a success** — judge test outcomes by the raw
exit code of `swift test`, never by the xcsift summary.

An Example app lives in `Example/` with its own `.xcodeproj` (depends on the library via local path).

## Key Constraints

- **Swift 6 strict concurrency** (`swift-tools-version: 6.2`, `swiftLanguageModes: [.v6]`). All new code must satisfy `Sendable` checking and actor isolation rules.
- **macOS 11+ deployment target**, but some UI code gates on newer OS versions (e.g., `NSSearchField.controlSize = .extraLarge` on macOS 26+).

## Architecture

RunningApplicationKit provides data models, observers, and picker UI for macOS running applications and BSD processes.

### Public API Boundary

Only `RunningPickerTabViewController` (and its configuration/delegate/column types), `RunningApplication`, `RunningProcess`, `RunningProcessEnumerator`, `RunningItem`, `Architecture`, and the two observer actors are `public`. The individual picker view controllers (`RunningApplicationPickerViewController`, `RunningProcessPickerViewController`) and the base class `RunningItemPickerViewController` are `internal` — consumers interact through the tab VC.

### Concurrency Model

- **Observers** (`RunningApplicationObserver`, `RunningProcessObserver`) are Swift `actor` types. `RunningApplicationObserver` uses KVO; `RunningProcessObserver` uses async `Task`-based polling.
- **Picker VCs** are `@MainActor` (implicit via `NSViewController`). `RunningProcessPickerViewController` offloads process enumeration to a background `DispatchQueue` and bounces results back to main.
- **`RunningProcessEnumerator`** guards its icon/architecture caches with `NSLock` and `nonisolated(unsafe)` storage.

### Low-Level System APIs

`BSDProcess` (internal) wraps several C/Darwin APIs — understanding these is important when debugging or extending process-related features:

- `proc_listpids` / `proc_pidpath` / `proc_name` — BSD process enumeration
- `proc_pidinfo` with `PROC_PIDARCHINFO` — architecture detection, reporting the architecture
  the kernel actually runs the process as (which is what distinguishes arm64 from arm64e)
- `sysctl` with `KERN_PROC_PID` — Rosetta translation detection via `p_flag & P_TRANSLATED`
- `csops` loaded via `dlsym` — code-signing status / sandbox detection
- Mach-O `LC_BUILD_VERSION` read straight from the executable file (`MachOPlatform.swift`) —
  platform detection, which is how simulator processes are identified. The kernel exposes no
  platform flavor: `proc_pidinfo` is public only up to `PROC_PIDARCHINFO` (19), and that
  returns plain `arm64` for simulator guests, identical to host processes.
- `LSApplicationProxy` accessed via `NSClassFromString` runtime reflection — entitlement-based sandbox detection for applications

### UI Inheritance Chain

`RunningItemPickerViewController<Item: RunningItem>` is a generic base class providing: search field, `NSTableViewDiffableDataSource`, column sorting, context menus, cancel/confirm buttons. Subclasses override hooks (`loadItems()`, `configureColumns()`, `makeCellView(for:item:)`, `compareItems(_:_:columnIdentifier:)`, etc.).

Cell views in `TableCellViews.swift` use distinct subclasses per column type (e.g., `NameTableCellView`, `PIDTableCellView`) — this enables `NSTableView` cell reuse by class identity via the `NSTableView.makeView(ofClass:modify:)` extension.
