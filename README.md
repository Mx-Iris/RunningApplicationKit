# RunningApplicationKit

A macOS library for enumerating, observing, and picking running applications and BSD processes.

Provides value-type models with architecture and sandbox detection, async observers for launch/termination events, and a ready-to-use picker UI with search, sorting, and context menus.

## Requirements

- macOS 11+
- Swift 6.2+

## Installation

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/Mx-Iris/RunningApplicationKit.git", from: "0.2.0")
]
```

## Usage

### Picker UI

Present a tabbed picker for selecting a running application or process:

```swift
import RunningApplicationKit

let picker = RunningPickerTabViewController()
picker.delegate = self

let window = NSWindow(contentViewController: picker)
window.makeKeyAndOrderFront(nil)
```

Handle selection via the delegate:

```swift
extension MyController: RunningPickerTabViewController.Delegate {
    func runningPickerTabViewController(
        _ viewController: RunningPickerTabViewController,
        didConfirmApplication application: RunningApplication
    ) {
        print(application.name, application.processIdentifier, application.bundleIdentifier ?? "")
    }

    func runningPickerTabViewController(
        _ viewController: RunningPickerTabViewController,
        didConfirmProcess process: RunningProcess
    ) {
        print(process.name, process.processIdentifier, process.executablePath ?? "")
    }
}
```

Customize columns and appearance through configuration:

```swift
let picker = RunningPickerTabViewController(
    applicationConfiguration: .init(
        title: "Choose an App",
        allowsColumns: [.icon, .name, .bundleIdentifier, .architecture]
    ),
    processConfiguration: .init(
        title: "Choose a Process",
        allowsColumns: [.icon, .name, .pid, .executablePath],
        refreshInterval: 3.0
    )
)
```

### Observing Applications

Watch for a specific application's launch and termination using KVO:

```swift
let observer = RunningApplicationObserver(observeApplicationBundleID: "com.apple.Safari")

await observer.onLaunch {
    print("Safari launched")
}
await observer.onTerminate {
    print("Safari terminated")
}
await observer.start()

// Later:
await observer.stop()
```

### Observing Processes

Watch for a process by name, PID, or executable path using timer-based polling:

```swift
let observer = RunningProcessObserver(target: .name("nginx"), pollingInterval: 2.0)

await observer.onLaunch {
    print("nginx started")
}
await observer.onTerminate {
    print("nginx stopped")
}
await observer.start()
```

### Enumerating Processes

List all running BSD processes (excluding GUI applications by default):

```swift
let processes = RunningProcessEnumerator.listProcesses()

for process in processes {
    print(process.name, process.processIdentifier, process.architecture?.description ?? "")
}
```

Build a model for a single PID:

```swift
if let process = RunningProcessEnumerator.makeProcess(for: 1234) {
    print(process.name, process.executablePath ?? "", process.isSandboxed)
}
```

### Data Models

`RunningApplication` wraps `NSRunningApplication` into a value type:

```swift
let app = RunningApplication(from: nsRunningApp)
app.processIdentifier  // pid_t
app.name               // String
app.bundleIdentifier   // String?
app.architecture       // Architecture? (.arm64, .x86_64, ...)
app.isSandboxed        // Bool
app.isActive           // Bool
app.activationPolicy   // NSApplication.ActivationPolicy
```

`RunningProcess` represents a BSD process:

```swift
process.processIdentifier  // pid_t
process.name               // String
process.executablePath     // String?
process.architecture       // Architecture?
process.isSandboxed        // Bool
```

Both conform to the `RunningItem` protocol (`processIdentifier`, `name`, `icon`, `architecture`).

## License

MIT License. See [LICENSE](LICENSE) for details.
