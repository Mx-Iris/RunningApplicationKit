import AppKit

enum ListRowColumn {
    /// Identifier of the single full-width column backing the list style.
    ///
    /// Lives here rather than on the picker because that type is generic, and Swift does
    /// not allow static stored properties in generic types.
    static let identifier = "listRow"
}

/// A marker rendered to the right of a list row's title.
///
/// Badges are deliberately rendered only when they carry information: a platform badge is
/// omitted for the host platform, and the sandbox badge appears only for sandboxed items.
/// Rendering every value the way a table column must is what produced the wall of repeated
/// "macOS" and the wall of red crosses that this style exists to remove.
enum ListRowBadge: Equatable {
    case text(String, Tone)
    case symbol(name: String, tone: Tone)

    enum Tone: Equatable {
        /// Reserved for what the row is being scanned for — simulator platforms.
        case emphasis
        /// Factual but unremarkable, e.g. Mac Catalyst or DriverKit.
        case neutral
        /// Something could not be determined.
        case caution
        /// A positive attribute worth noticing, e.g. sandboxed.
        case affirmative
    }
}

extension ListRowBadge.Tone {
    var foregroundColor: NSColor {
        switch self {
        case .emphasis: .controlAccentColor
        case .neutral: .secondaryLabelColor
        case .caution: .systemOrange
        case .affirmative: .systemGreen
        }
    }

    var backgroundColor: NSColor {
        switch self {
        case .emphasis: .controlAccentColor.withAlphaComponent(0.16)
        case .neutral: .quaternaryLabelColor.withAlphaComponent(0.5)
        case .caution: .systemOrange.withAlphaComponent(0.16)
        case .affirmative: .systemGreen.withAlphaComponent(0.16)
        }
    }
}

/// A pill carrying either a short label or a symbol.
private final class BadgeView: NSView {
    private let label = NSTextField(labelWithString: "")
    private let symbolView = NSImageView()

    init(badge: ListRowBadge) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 4
        translatesAutoresizingMaskIntoConstraints = false
        setContentCompressionResistancePriority(.required, for: .horizontal)
        setContentHuggingPriority(.required, for: .horizontal)

        switch badge {
        case .text(let string, let tone):
            addSubview(label)
            label.translatesAutoresizingMaskIntoConstraints = false
            label.stringValue = string
            label.font = .systemFont(ofSize: 10, weight: .semibold)
            label.textColor = tone.foregroundColor
            layer?.backgroundColor = tone.backgroundColor.cgColor
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 5),
                trailingAnchor.constraint(equalTo: label.trailingAnchor, constant: 5),
                label.topAnchor.constraint(equalTo: topAnchor, constant: 1.5),
                bottomAnchor.constraint(equalTo: label.bottomAnchor, constant: 1.5),
            ])

        case .symbol(let name, let tone):
            addSubview(symbolView)
            symbolView.translatesAutoresizingMaskIntoConstraints = false
            symbolView.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
            symbolView.contentTintColor = tone.foregroundColor
            symbolView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
            layer?.backgroundColor = tone.backgroundColor.cgColor
            NSLayoutConstraint.activate([
                symbolView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
                trailingAnchor.constraint(equalTo: symbolView.trailingAnchor, constant: 4),
                symbolView.topAnchor.constraint(equalTo: topAnchor, constant: 2),
                bottomAnchor.constraint(equalTo: symbolView.bottomAnchor, constant: 2),
            ])
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

/// The single full-width cell backing the list style: an icon, a title with trailing
/// badges, and a subtitle carrying the remaining fields.
///
/// The subtitle truncates in the middle rather than at the tail, because for an executable
/// path the tail is the part worth reading.
final class ListRowTableCellView: TableCellView {
    private let iconImageView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let badgeStackView = NSStackView()
    private let titleRowStackView = NSStackView()
    private let textStackView = NSStackView()

    private var iconWidthConstraint: NSLayoutConstraint?
    private var iconHeightConstraint: NSLayoutConstraint?
    private var iconLeadingConstraint: NSLayoutConstraint?
    private var textLeadingToIconConstraint: NSLayoutConstraint?
    private var textLeadingToEdgeConstraint: NSLayoutConstraint?

    var iconSize: CGFloat = 22 {
        didSet {
            guard iconSize != oldValue else { return }
            iconWidthConstraint?.constant = iconSize
            iconHeightConstraint?.constant = iconSize
        }
    }

    var image: NSImage? {
        didSet {
            iconImageView.image = image
            updateIconVisibility()
        }
    }

    /// Whether the row reserves space for an icon at all. False when `.icon` is absent
    /// from the configured fields, so the text starts at the leading edge.
    var showsIcon: Bool = true {
        didSet {
            guard showsIcon != oldValue else { return }
            updateIconVisibility()
        }
    }

    var title: String? {
        didSet {
            titleLabel.stringValue = title ?? ""
        }
    }

    var subtitle: String? {
        didSet {
            subtitleLabel.stringValue = subtitle ?? ""
            subtitleLabel.isHidden = (subtitle ?? "").isEmpty
            toolTip = [title, subtitle].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n")
        }
    }

    var badges: [ListRowBadge] = [] {
        didSet {
            guard badges != oldValue else { return }
            rebuildBadges()
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        iconImageView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(iconImageView)

        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        subtitleLabel.font = .systemFont(ofSize: 11, weight: .regular)
        subtitleLabel.textColor = .secondaryLabelColor
        // The tail of a path is the informative half, so give up the middle instead.
        subtitleLabel.lineBreakMode = .byTruncatingMiddle
        subtitleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        badgeStackView.orientation = .horizontal
        badgeStackView.spacing = 4
        badgeStackView.alignment = .centerY
        badgeStackView.setContentCompressionResistancePriority(.required, for: .horizontal)
        badgeStackView.setContentHuggingPriority(.required, for: .horizontal)

        titleRowStackView.orientation = .horizontal
        titleRowStackView.spacing = 6
        titleRowStackView.alignment = .centerY
        titleRowStackView.addArrangedSubview(titleLabel)
        titleRowStackView.addArrangedSubview(badgeStackView)

        textStackView.orientation = .vertical
        textStackView.spacing = 1
        textStackView.alignment = .leading
        textStackView.translatesAutoresizingMaskIntoConstraints = false
        textStackView.addArrangedSubview(titleRowStackView)
        textStackView.addArrangedSubview(subtitleLabel)
        addSubview(textStackView)

        let iconWidth = iconImageView.widthAnchor.constraint(equalToConstant: iconSize)
        let iconHeight = iconImageView.heightAnchor.constraint(equalToConstant: iconSize)
        let iconLeading = iconImageView.leadingAnchor.constraint(equalTo: leadingAnchor)
        let textLeadingToIcon = textStackView.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: 8)
        let textLeadingToEdge = textStackView.leadingAnchor.constraint(equalTo: leadingAnchor)
        iconWidthConstraint = iconWidth
        iconHeightConstraint = iconHeight
        iconLeadingConstraint = iconLeading
        textLeadingToIconConstraint = textLeadingToIcon
        textLeadingToEdgeConstraint = textLeadingToEdge

        NSLayoutConstraint.activate([
            iconLeading,
            iconWidth,
            iconHeight,
            iconImageView.centerYAnchor.constraint(equalTo: centerYAnchor),

            textLeadingToIcon,
            textStackView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            textStackView.centerYAnchor.constraint(equalTo: centerYAnchor),
            textStackView.topAnchor.constraint(greaterThanOrEqualTo: topAnchor),
            bottomAnchor.constraint(greaterThanOrEqualTo: textStackView.bottomAnchor),

            titleRowStackView.widthAnchor.constraint(lessThanOrEqualTo: textStackView.widthAnchor),
            subtitleLabel.widthAnchor.constraint(lessThanOrEqualTo: textStackView.widthAnchor),
        ])
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        image = nil
        title = nil
        subtitle = nil
        badges = []
    }

    private func updateIconVisibility() {
        let visible = showsIcon
        iconImageView.isHidden = !visible
        iconWidthConstraint?.constant = visible ? iconSize : 0
        textLeadingToIconConstraint?.isActive = visible
        textLeadingToEdgeConstraint?.isActive = !visible
    }

    private func rebuildBadges() {
        for view in badgeStackView.arrangedSubviews {
            badgeStackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        for badge in badges {
            badgeStackView.addArrangedSubview(BadgeView(badge: badge))
        }
        badgeStackView.isHidden = badges.isEmpty
    }
}
