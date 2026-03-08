# Process-Level Support Design

## Overview

Extend RunningApplicationKit to support system processes beyond just `NSRunningApplication`. Add a process picker UI (tab-based, alongside the existing app picker) and a process observer.

## Architecture

### Data Models

**`RunningItem` protocol** — common interface for both models:

```swift
public protocol RunningItem: Hashable, Sendable {
    var pid: pid_t { get }
    var name: String { get }
    var icon: NSImage? { get }
    var architecture: Architecture? { get }
}
```

**`RunningApplication`** — wraps `NSRunningApplication`:

- pid, name, bundleIdentifier, icon, architecture, isSandboxed
- Constructed via `init(from: NSRunningApplication)`

**`RunningProcess`** — wraps BSD process info:

- pid, name, executablePath, icon, architecture
- Obtained via `proc_listpids` + `proc_pidinfo` / `proc_pidpath`
- Icon from `NSWorkspace.shared.icon(forFile:)` or generic fallback
- Excludes processes already present in `NSWorkspace.runningApplications`

### Observer

**`RunningProcessObserver`** (actor) — mirrors `RunningApplicationObserver` API:

- **Target**: `.pid(pid_t)`, `.name(String)`, `.executablePath(String)`
- **Detection**: Timer-based polling of `proc_listpids`, comparing against known PID set
- **Callbacks**: `onLaunch`, `onTerminate` (async setters)
- **Lifecycle**: `start()` / `stop()`
- **Polling interval**: Configurable, default 2 seconds

### UI

**`RunningItemPickerViewController<Item: RunningItem>`** — abstract generic base class:

- Common UI: title stack, search field, table view with diffable data source, cancel/confirm buttons
- Subclass hooks: `loadItems()`, `filterItems(_:searchText:)`, `configureColumns()`, `configureCell(column:item:)`, `contextMenuItems(for:)`

**`RunningApplicationPickerViewController`** — inherits base class with `RunningApplication`:

- Columns: icon, name, bundleIdentifier, pid, architecture, sandboxed
- Data from `NSWorkspace.runningApplications`

**`RunningProcessPickerViewController`** — inherits base class with `RunningProcess`:

- Columns: icon, name, pid, architecture (+ executablePath if desired)
- Data from BSD `proc_listpids`
- Timer-based refresh for the process list

**`RunningPickerTabViewController`** (NSTabViewController):

- Tab 1: "Applications" → `RunningApplicationPickerViewController`
- Tab 2: "Processes" → `RunningProcessPickerViewController`

### File Structure

```
Sources/RunningApplicationKit/
├── RunningItem.swift                              # Protocol
├── RunningApplication.swift                       # App model
├── RunningProcess.swift                           # Process model + BSD API
├── RunningApplicationObserver.swift               # Existing, unchanged
├── RunningProcessObserver.swift                   # New observer
├── RunningItemPickerViewController.swift          # Generic base class
├── RunningApplicationPickerViewController.swift   # Refactored, inherits base
├── RunningProcessPickerViewController.swift       # New, inherits base
├── RunningPickerTabViewController.swift           # Tab container
└── Extensions/
    ├── NSRunningApplication+Extensions.swift      # Extracted from existing
    ├── NSTableView+Extensions.swift               # Extracted from existing
    └── NSImage+Extensions.swift                   # Extracted from existing
```

## Key Decisions

- BSD system calls (`proc_listpids`, `proc_pidinfo`, `proc_pidpath`) for process enumeration
- Timer-based polling for process list refresh and observer (no event-driven API for new process detection)
- Common base class with generics to share UI layout and logic
- Separate Column enums per subclass (different available columns)
- Separate Delegate protocols per subclass (different callback parameter types)
- Processes already in `NSWorkspace.runningApplications` are excluded from the process list
