# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Test

This is a pure Swift Package Manager library (no Xcode project).

```bash
swift package update && swift build 2>&1 | xcsift
```

There are no tests in this project.

## Architecture

RunningApplicationKit is a macOS library (minimum macOS 11) providing components for working with running applications and system processes.

### Data Models

- **`RunningItem`** — Protocol defining the common interface (`pid`, `name`, `icon`, `architecture`) shared by both application and process models.
- **`RunningApplication`** — Value type wrapping `NSRunningApplication` with pid, name, bundleIdentifier, icon, architecture, and isSandboxed.
- **`RunningProcess`** — Value type representing a BSD process with pid, name, executablePath, icon, and architecture. Enumerated via `RunningProcessEnumerator` using `proc_listpids`/`proc_pidpath`.
- **`Architecture`** — Standalone enum (x86_64, arm64, i386, ppc, ppc64, unknown) used by both models.

### Observers

- **`RunningApplicationObserver`** — A Swift actor that uses KVO on `NSWorkspace.runningApplications` to observe launch/termination of a specific app by bundle identifier. Exposes async `onLaunch`/`onTerminate` callback setters and `start()`/`stop()` lifecycle methods.
- **`RunningProcessObserver`** — A Swift actor that uses timer-based polling of `proc_listpids` to detect process launch/termination. Supports targeting by `.pid`, `.name`, or `.executablePath`.

### UI Components

- **`RunningItemPickerViewController<Item: RunningItem>`** — Generic base class providing common picker UI: title/description labels, search field, table view with `NSTableViewDiffableDataSource`, cancel/confirm buttons, and context menu support. Subclasses override hooks (`loadItems()`, `configureColumns()`, `makeCellView(for:item:)`, etc.).
- **`RunningApplicationPickerViewController`** — Inherits base class with `RunningApplication`. Columns: icon, name, bundleIdentifier, pid, architecture, sandboxed. Sandbox detection uses `LSApplicationProxy` from **LaunchServicesPrivate**.
- **`RunningProcessPickerViewController`** — Inherits base class with `RunningProcess`. Columns: icon, name, pid, architecture, executablePath. Timer-based refresh of the process list.
- **`RunningPickerTabViewController`** — `NSTabViewController` wrapping both pickers in "Applications" and "Processes" tabs.

### Shared Components

- **`TableCellViews.swift`** — Shared cell view classes (`IconTableCellView`, `LabelTableCellView`, `CheckboxTableCellView`).
- **`Extensions/`** — `NSTableView` (typed cell view reuse), `NSRunningApplication` (architecture, sandbox check), `NSImage` (SF Symbol constants).
