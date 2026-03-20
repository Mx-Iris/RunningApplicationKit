# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Test

Pure Swift Package Manager library. No Xcode project, no external dependencies.

```bash
swift package update && swift build 2>&1 | xcsift
```

There are no tests in this project.

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
- Mach-O header reading (`mach_header_64`, `fat_header`) — architecture detection from executable binaries
- `sysctl` with `KERN_PROC_PID` — Rosetta translation detection via `p_flag & P_TRANSLATED`
- `csops` loaded via `dlsym` — code-signing status / sandbox detection
- `LSApplicationProxy` accessed via `NSClassFromString` runtime reflection — entitlement-based sandbox detection for applications

### UI Inheritance Chain

`RunningItemPickerViewController<Item: RunningItem>` is a generic base class providing: search field, `NSTableViewDiffableDataSource`, column sorting, context menus, cancel/confirm buttons. Subclasses override hooks (`loadItems()`, `configureColumns()`, `makeCellView(for:item:)`, `compareItems(_:_:columnIdentifier:)`, etc.).

Cell views in `TableCellViews.swift` use distinct subclasses per column type (e.g., `NameTableCellView`, `PIDTableCellView`) — this enables `NSTableView` cell reuse by class identity via the `NSTableView.makeView(ofClass:modify:)` extension.
