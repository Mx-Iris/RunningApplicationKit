import AppKit
import Testing
@testable import RunningApplicationKit

/// The tests in this target that read real processes: the test process itself
/// and children it starts. Every other test is independent of the machine.
@Suite("Local processes", .serialized)
struct LocalProcessTests {
    @Test("the test process is described by its executable's name and the macOS platform")
    func currentProcessIsDescribed() throws {
        let process = try #require(RunningProcessEnumerator.makeProcess(for: getpid()))

        #expect(process.name == ProcessInfo.processInfo.processName)
        #expect(process.platform == .macOS)
    }

    @Test("a running application reports the platform of its process")
    func runningApplicationReportsPlatform() throws {
        // The test runner is not an application to Launch Services, so its
        // `NSRunningApplication.current` has no process identifier; Finder
        // runs whenever someone is logged in.
        let finder = try #require(NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == "com.apple.finder" })

        let application = RunningApplication(from: finder, resolveSandbox: false)

        #expect(application.platform == .macOS)
    }

    @Test("observing by name matches the name the kernel keeps, cut to 31 bytes, and the executable's whole file name")
    func observingByNameReportsLaunchAndTermination() async throws {
        let executable = try UniquelyNamedExecutable(copying: "/bin/sleep")
        let kernelName = String(executable.name.prefix(31))
        try #require(kernelName != executable.name)
        let kernelNameEvents = ObservedEvents()
        let fileNameEvents = ObservedEvents()
        let kernelNameObserver = RunningProcessObserver(target: .name(kernelName), pollingInterval: 0.05)
        let fileNameObserver = RunningProcessObserver(target: .name(executable.name), pollingInterval: 0.05)
        await kernelNameObserver.onLaunch { kernelNameEvents.record(.launch) }
        await kernelNameObserver.onTerminate { kernelNameEvents.record(.termination) }
        await fileNameObserver.onLaunch { fileNameEvents.record(.launch) }
        await fileNameObserver.onTerminate { fileNameEvents.record(.termination) }
        await kernelNameObserver.start()
        await fileNameObserver.start()
        // Lets the first scans finish, so the launch is a change they can see.
        try await Task.sleep(nanoseconds: 200_000_000)

        let child = try ChildProcess(executablePath: executable.path, arguments: ["60"])
        _ = await eventually { kernelNameEvents.contains(.launch) && fileNameEvents.contains(.launch) }
        #expect(kernelNameEvents.contains(.launch))
        #expect(fileNameEvents.contains(.launch))

        child.kill()
        _ = await eventually { kernelNameEvents.contains(.termination) && fileNameEvents.contains(.termination) }
        #expect(kernelNameEvents.contains(.termination))
        #expect(fileNameEvents.contains(.termination))

        await kernelNameObserver.stop()
        await fileNameObserver.stop()
    }

    @available(macOS 15, *)
    @Test("observing by identifier reports termination without waiting for the polling interval")
    func observingByIdentifierReportsTerminationAtOnce() async throws {
        let child = try ChildProcess(executablePath: "/bin/sleep", arguments: ["60"])
        let events = ObservedEvents()
        let observer = RunningProcessObserver(target: .pid(child.processIdentifier), pollingInterval: 30)
        await observer.onTerminate { events.record(.termination) }
        await observer.start()
        // Lets the first scan see the child running.
        try await Task.sleep(nanoseconds: 200_000_000)

        child.kill()

        #expect(await eventually(timeout: 3) { events.contains(.termination) })
        await observer.stop()
    }
}

// MARK: - Support

/// What a ``RunningProcessObserver`` reported, recorded from its handlers.
private final class ObservedEvents: @unchecked Sendable {
    enum Event: Hashable {
        case launch
        case termination
    }

    private let lock = NSLock()
    private var events: [Event] = []

    func record(_ event: Event) {
        lock.withLock { events.append(event) }
    }

    func contains(_ event: Event) -> Bool {
        lock.withLock { events.contains(event) }
    }
}

/// A child process the test kills, or that is killed when the test lets go of it.
private final class ChildProcess {
    private let process = Process()

    init(executablePath: String, arguments: [String]) throws {
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        try process.run()
    }

    var processIdentifier: pid_t {
        process.processIdentifier
    }

    /// Kills the child with `SIGKILL`, which the test runner cannot have
    /// blocked, and waits until it has been reaped.
    func kill() {
        guard process.isRunning else { return }
        _ = Darwin.kill(process.processIdentifier, SIGKILL)
        process.waitUntilExit()
    }

    deinit {
        kill()
    }
}

/// A copy of an executable under a file name no other process has, longer
/// than the 31 bytes of it the kernel reports as the process's name.
///
/// A symbolic link would not do: the kernel names a process after the file a
/// link resolves to, not after the link.
private final class UniquelyNamedExecutable {
    let name: String
    let path: String
    private let directory: URL

    init(copying sourcePath: String) throws {
        name = "ObserverTest-\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RunningApplicationKitTests-\(UUID().uuidString)", isDirectory: true)
        path = directory.appendingPathComponent(name).path
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.copyItem(atPath: sourcePath, toPath: path)
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }
}

/// Polls `condition` until it holds or `timeout` seconds pass.
private func eventually(timeout: TimeInterval = 5, _ condition: () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() {
            return true
        }
        try? await Task.sleep(nanoseconds: 20_000_000)
    }
    return condition()
}
