import AppKit
import RunningApplicationKit

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: NSWindowController!

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        let tabViewController = RunningPickerTabViewController()
        tabViewController.delegate = self

        let window = NSWindow(contentViewController: tabViewController)
        window.title = "RunningApplicationKit Demo"
        window.setContentSize(NSSize(width: 900, height: 650))
        window.center()

        windowController = NSWindowController(window: window)
        windowController.showWindow(nil)
    }

    func applicationWillTerminate(_ aNotification: Notification) {}

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

extension AppDelegate: RunningPickerTabViewController.Delegate {
    func runningPickerTabViewController(_ viewController: RunningPickerTabViewController, didConfirmApplication application: RunningApplication) {
        let alert = NSAlert()
        alert.messageText = "Selected Application"
        alert.informativeText = """
        Name: \(application.name)
        PID: \(application.processIdentifier)
        Bundle ID: \(application.bundleIdentifier ?? "N/A")
        Architecture: \(application.architecture?.description ?? "Unknown")
        Sandboxed: \(application.isSandboxed)
        """
        alert.runModal()
    }

    func runningPickerTabViewController(_ viewController: RunningPickerTabViewController, didConfirmProcess process: RunningProcess) {
        let alert = NSAlert()
        alert.messageText = "Selected Process"
        alert.informativeText = """
        Name: \(process.name)
        PID: \(process.processIdentifier)
        Path: \(process.executablePath ?? "N/A")
        """
        alert.runModal()
    }

    func runningPickerTabViewControllerWasCancelled(_ viewController: RunningPickerTabViewController) {
        NSApp.terminate(nil)
    }
}
