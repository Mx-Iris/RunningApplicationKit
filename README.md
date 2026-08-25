# RunningApplicationKit

A macOS library for enumerating, observing, and picking running applications and BSD processes.

Provides value-type models with architecture, platform, and sandbox detection, async observers for launch/termination events, and a ready-to-use picker UI with search, sorting, and context menus.

Platform detection identifies which platform a process's binary was built for — notably telling simulator processes apart from host ones, which architecture alone cannot do: on Apple Silicon a process inside an iOS Simulator runs as native `arm64`, exactly like its host counterparts.

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

Find the processes running inside a simulator:

```swift
let simulated = RunningProcessEnumerator.listProcesses()
    .filter { $0.platform?.isSimulator == true }
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
app.platform           // Platform? (.macOS, .macCatalyst, ...)
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
process.platform           // Platform? (.iOSSimulator, .macOS, ...)
process.isSandboxed        // Bool
```

Both conform to the `RunningItem` protocol (`processIdentifier`, `name`, `icon`, `architecture`,
`isSandboxed`, `platform`).

### Platform

`Platform` mirrors the `PLATFORM_*` constants of a binary's Mach-O `LC_BUILD_VERSION` load
command, read from the executable on disk and cached per path:

```swift
process.platform             // .iOSSimulator
process.platform?.isSimulator // true for iOS/tvOS/watchOS/visionOS simulators
process.platform?.description // "iOS Simulator"
```

Constants this version does not recognize are preserved as `.unknown(rawValue)` rather than
discarded, since Apple extends the table most years.

`platform` is `nil` when the executable cannot be read — typically a protected system process
whose path `proc_pidpath` will not report. On the development machine that is about 5% of all
processes, the same set for which `architecture` is also unavailable.

## License

MIT License. See [LICENSE](LICENSE) for details.
