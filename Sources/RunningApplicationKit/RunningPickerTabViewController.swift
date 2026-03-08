import AppKit

public final class RunningPickerTabViewController: NSTabViewController {
    public let applicationPickerViewController: RunningApplicationPickerViewController
    public let processPickerViewController: RunningProcessPickerViewController

    public init(
        applicationConfiguration: RunningApplicationPickerViewController.Configuration = .init(),
        processConfiguration: RunningProcessPickerViewController.Configuration = .init()
    ) {
        self.applicationPickerViewController = RunningApplicationPickerViewController(configuration: applicationConfiguration)
        self.processPickerViewController = RunningProcessPickerViewController(configuration: processConfiguration)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        preferredContentSize = .init(width: 800, height: 600)

        let appTabItem = NSTabViewItem(viewController: applicationPickerViewController)
        appTabItem.label = "Applications"

        let processTabItem = NSTabViewItem(viewController: processPickerViewController)
        processTabItem.label = "Processes"

        addTabViewItem(appTabItem)
        addTabViewItem(processTabItem)
    }
}

import SwiftUI

@available(macOS 14.0, *)
#Preview(traits: .fixedLayout(width: 800, height: 700)) {
    RunningPickerTabViewController()
}
