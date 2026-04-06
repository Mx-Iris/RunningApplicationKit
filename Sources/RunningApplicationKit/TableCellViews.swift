import AppKit

class TableCellView: NSTableCellView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

class IconTableCellView: TableCellView {
    var tintColor: NSColor? {
        didSet {
            iconImageView.contentTintColor = tintColor
        }
    }

    var image: NSImage? {
        didSet {
            iconImageView.image = image
        }
    }

    fileprivate let iconImageView = NSImageView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(iconImageView)
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            iconImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconImageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconImageView.heightAnchor.constraint(equalTo: heightAnchor),
            iconImageView.widthAnchor.constraint(equalTo: heightAnchor),
        ])
    }
}

class StatusIconTableCellView: IconTableCellView {
    var isLoading: Bool = false {
        didSet {
            iconImageView.isHidden = isLoading
            if isLoading {
                spinner.startAnimation(nil)
            } else {
                spinner.stopAnimation(nil)
            }
            spinner.isHidden = !isLoading
        }
    }

    private let spinner = NSProgressIndicator()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(spinner)
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isHidden = true
        NSLayoutConstraint.activate([
            spinner.centerYAnchor.constraint(equalTo: centerYAnchor),
            spinner.centerXAnchor.constraint(equalTo: centerXAnchor),
        ])
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        isLoading = false
        image = nil
        tintColor = nil
    }
}

class NameTableCellView: LabelTableCellView {}

class BundleIdentifierTableCellView: LabelTableCellView {}

class PIDTableCellView: LabelTableCellView {}

class ArchitectureTableCellView: LabelTableCellView {}

class ExecutablePathTableCellView: LabelTableCellView {}

class LabelTableCellView: TableCellView {
    var string: String? {
        didSet {
            label.stringValue = string ?? ""
            toolTip = label.stringValue
        }
    }

    private let label = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 12, weight: .regular)
        label.lineBreakMode = .byTruncatingTail
        NSLayoutConstraint.activate([
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            label.topAnchor.constraint(greaterThanOrEqualTo: topAnchor),
            label.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
        ])
    }
}
