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

    private let iconImageView = NSImageView()

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

class LabelTableCellView: TableCellView {
    var string: String? {
        didSet {
            label.stringValue = string ?? ""
            toolTip = label.stringValue
        }
    }

    var attributedString: NSAttributedString? {
        didSet {
            label.attributedStringValue = attributedString ?? NSAttributedString()
            toolTip = label.attributedStringValue.string
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

class CheckboxTableCellView: TableCellView {
    var isChecked: Bool = false {
        didSet {
            checkbox.state = isChecked ? .on : .off
        }
    }

    var isEnabled: Bool = false {
        didSet {
            checkbox.isEnabled = isEnabled
        }
    }

    private let checkbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(checkbox)
        checkbox.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            checkbox.centerYAnchor.constraint(equalTo: centerYAnchor),
            checkbox.centerXAnchor.constraint(equalTo: centerXAnchor),
        ])
    }
}
