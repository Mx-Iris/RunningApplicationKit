import Cocoa
import RunningApplicationKit

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: NSWindowController!

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        let tabViewController = RunningPickerTabViewController()
        tabViewController.applicationPickerViewController.delegate = self
        tabViewController.processPickerViewController.delegate = self

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

extension AppDelegate: RunningApplicationPickerViewController.Delegate {
    func runningApplicationPickerViewController(_ viewController: RunningApplicationPickerViewController, didConfirmApplication application: RunningApplication) {
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

    func runningApplicationPickerViewControllerWasCancelled(_ viewController: RunningApplicationPickerViewController) {
        NSApp.terminate(nil)
    }
}

extension AppDelegate: RunningProcessPickerViewController.Delegate {
    func runningProcessPickerViewController(_ viewController: RunningProcessPickerViewController, didConfirmProcess process: RunningProcess) {
        let alert = NSAlert()
        alert.messageText = "Selected Process"
        alert.informativeText = """
        Name: \(process.name)
        PID: \(process.processIdentifier)
        Path: \(process.executablePath ?? "N/A")
        """
        alert.runModal()
    }

    func runningProcessPickerViewControllerWasCancelled(_ viewController: RunningProcessPickerViewController) {
        NSApp.terminate(nil)
    }
}
