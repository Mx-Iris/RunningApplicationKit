import AppKit

// MARK: - SkeletonAppearance

/// Tunable knobs for the loading skeleton's colors, shapes, sizes, and shimmer.
/// All properties have sensible defaults; override individual fields to nudge
/// alignment, contrast, or animation feel.
public struct SkeletonAppearance {
    /// How the icon-style placeholder picks its width/height.
    public enum IconSizeMode {
        /// Fill the row height exactly — matches `IconTableCellView`.
        case fillCellHeight
        /// Use a fixed point size.
        case fixed(CGFloat)
        /// Use `cellHeight - 2 * inset` (clamped to >= 0).
        case insetBy(CGFloat)

        func size(forCellHeight cellHeight: CGFloat) -> CGFloat {
            switch self {
            case .fillCellHeight: return cellHeight
            case .fixed(let value): return value
            case .insetBy(let inset): return max(0, cellHeight - 2 * inset)
            }
        }
    }

    // Colors
    public var baseColor: NSColor
    public var highlightColor: NSColor

    // Corner radius per style
    public var iconCornerRadius: CGFloat
    public var textCornerRadius: CGFloat

    // Icon-style placeholder geometry
    public var iconSizeMode: IconSizeMode
    public var iconVerticalOffset: CGFloat

    // Text-style placeholder geometry
    public var textBarHeight: CGFloat
    public var textBarLeadingInset: CGFloat
    public var textBarTrailingInset: CGFloat
    public var textBarVerticalOffset: CGFloat

    /// Width fractions for text-style placeholders. Looked up as
    /// `textBarWidthFractions[rowIndex % rows.count][columnIndex % cols.count]`.
    /// Use a non-uniform pattern to suggest text of varying lengths.
    public var textBarWidthFractions: [[CGFloat]]

    // Shimmer animation
    public var shimmerDuration: TimeInterval
    public var shimmerRowStagger: TimeInterval
    public var shimmerColumnStagger: TimeInterval

    /// Padding around the row area (the part of the overlay below the column
    /// header). `top`/`bottom` push the first/last row inward and shrink the
    /// background fill. `left`/`right` only shrink the background fill —
    /// placeholders stay anchored to the real table column frames so column
    /// alignment is preserved.
    public var contentInsets: NSEdgeInsets

    public init(
        baseColor: NSColor = NSColor.tertiaryLabelColor.withAlphaComponent(0.32),
        highlightColor: NSColor = NSColor.labelColor.withAlphaComponent(0.14),
        iconCornerRadius: CGFloat = 5,
        textCornerRadius: CGFloat = 3,
        iconSizeMode: IconSizeMode = .fillCellHeight,
        iconVerticalOffset: CGFloat = 0,
        textBarHeight: CGFloat = 10,
        textBarLeadingInset: CGFloat = 0,
        textBarTrailingInset: CGFloat = 0,
        textBarVerticalOffset: CGFloat = 0,
        textBarWidthFractions: [[CGFloat]] = SkeletonAppearance.defaultTextBarWidthFractions,
        shimmerDuration: TimeInterval = 1.4,
        shimmerRowStagger: TimeInterval = 0.08,
        shimmerColumnStagger: TimeInterval = 0.05,
        contentInsets: NSEdgeInsets = NSEdgeInsets(top: 8, left: 0, bottom: 8, right: 0),
    ) {
        self.baseColor = baseColor
        self.highlightColor = highlightColor
        self.iconCornerRadius = iconCornerRadius
        self.textCornerRadius = textCornerRadius
        self.iconSizeMode = iconSizeMode
        self.iconVerticalOffset = iconVerticalOffset
        self.textBarHeight = textBarHeight
        self.textBarLeadingInset = textBarLeadingInset
        self.textBarTrailingInset = textBarTrailingInset
        self.textBarVerticalOffset = textBarVerticalOffset
        self.textBarWidthFractions = textBarWidthFractions
        self.shimmerDuration = shimmerDuration
        self.shimmerRowStagger = shimmerRowStagger
        self.shimmerColumnStagger = shimmerColumnStagger
        self.contentInsets = contentInsets
    }

    public static let defaultTextBarWidthFractions: [[CGFloat]] = [
        [0.78, 0.55, 0.60, 0.70, 0.50, 0.65],
        [0.60, 0.78, 0.55, 0.65, 0.70, 0.50],
        [0.85, 0.50, 0.72, 0.55, 0.65, 0.75],
        [0.55, 0.82, 0.60, 0.75, 0.50, 0.70],
        [0.70, 0.65, 0.78, 0.50, 0.82, 0.55],
        [0.65, 0.72, 0.55, 0.80, 0.60, 0.68],
    ]
}

// MARK: - SkeletonColumnDescriptor

struct SkeletonColumnDescriptor {
    enum Style {
        case icon
        case text
    }

    var identifier: String
    var style: Style
    var alignment: NSTextAlignment
}

// MARK: - SkeletonListView

/// Vertical list of skeleton rows. Reads per-column frames from a reference
/// NSTableView so placeholders stay aligned with inset-style padding,
/// intercell spacing, and last-column stretch.
final class SkeletonListView: NSView {
    weak var tableView: NSTableView? {
        didSet { needsLayout = true }
    }

    var rowHeight: CGFloat = 25 {
        didSet {
            guard rowHeight != oldValue else { return }
            needsLayout = true
        }
    }

    var rowSpacing: CGFloat = 10 {
        didSet {
            guard rowSpacing != oldValue else { return }
            needsLayout = true
        }
    }

    var columns: [SkeletonColumnDescriptor] = [] {
        didSet { rebuildRowsContent() }
    }

    var skeletonAppearance: SkeletonAppearance = .init() {
        didSet {
            for row in rowViews {
                row.applyAppearance(skeletonAppearance)
            }
            needsLayout = true
        }
    }

    private var rowViews: [SkeletonRowView] = []
    private let backgroundFillView = SkeletonBackgroundFillView()
    private(set) var isAnimating = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        // Opaque fill that sits below the row placeholders. When the overlay
        // is fully visible (alpha == 1) this fully occludes the table content
        // underneath; at lower alpha values the content shows through.
        addSubview(backgroundFillView)
        clipsToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    // Skeleton is a passive overlay — never intercept clicks. Lets the user
    // focus the search field / interact with controls even while loading.
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func layout() {
        super.layout()
        let topInset = computeTopInset()
        let insets = skeletonAppearance.contentInsets
        let rowAreaTop = topInset + insets.top
        let rowAreaBottom = max(rowAreaTop, bounds.height - insets.bottom)
        backgroundFillView.frame = .init(
            x: 0,
            y: 0,
            width: bounds.width,
            height: bounds.height,
        )
        let pitch = rowHeight + rowSpacing
        let availableHeight = rowAreaBottom - rowAreaTop
        guard pitch > 0, availableHeight > 0 else { return }
        let neededRows = max(1, Int(ceil(availableHeight / pitch)))
        if rowViews.count != neededRows {
            rebuildRows(count: neededRows)
        }
        let columnFrames = computeColumnFrames()
        var y: CGFloat = rowAreaTop
        for row in rowViews {
            row.frame = .init(x: 0, y: y, width: bounds.width, height: rowHeight)
            row.columnFrames = columnFrames
            y += rowHeight + rowSpacing
        }
    }

    // Reserve the vertical gap (if any) between this overlay's top edge and
    // the tableView's top edge — i.e. the column header — so skeleton rows
    // don't paint over it. Works regardless of whether the header lives inside
    // or outside the scroll view's clip view.
    private func computeTopInset() -> CGFloat {
        guard let tableView else { return 0 }
        let tableTopInSelf = tableView.convert(NSPoint.zero, to: self).y
        return max(0, tableTopInSelf)
    }

    private func rebuildRows(count: Int) {
        rowViews.forEach { $0.removeFromSuperview() }
        rowViews = (0 ..< count).map { index in
            let row = SkeletonRowView(rowIndex: index, columns: columns, appearance: skeletonAppearance)
            addSubview(row)
            if isAnimating {
                row.startAnimating()
            }
            return row
        }
    }

    private func rebuildRowsContent() {
        for row in rowViews {
            row.update(columns: columns)
        }
    }

    // tableView lives inside scrollView.contentView, and this view is sized to
    // contentView too. With no horizontal scroll their x origins coincide, so
    // tableView column rects can be reused directly as skeleton column rects.
    private func computeColumnFrames() -> [String: CGRect] {
        guard let tableView else { return [:] }
        var result: [String: CGRect] = [:]
        for (columnIndex, tableColumn) in tableView.tableColumns.enumerated() {
            result[tableColumn.identifier.rawValue] = tableView.rect(ofColumn: columnIndex)
        }
        return result
    }

    func startAnimating() {
        guard !isAnimating else { return }
        isAnimating = true
        rowViews.forEach { $0.startAnimating() }
    }

    func stopAnimating() {
        guard isAnimating else { return }
        isAnimating = false
        rowViews.forEach { $0.stopAnimating() }
    }
}

// MARK: - SkeletonRowView

/// A single skeleton row. Reads each column's frame from `columnFrames` keyed
/// by column identifier and places one placeholder per descriptor inside that slot.
final class SkeletonRowView: NSView {
    private let rowIndex: Int
    private var columns: [SkeletonColumnDescriptor]
    private var placeholders: [SkeletonPlaceholderView] = []
    private var skeletonAppearance: SkeletonAppearance

    var columnFrames: [String: CGRect] = [:] {
        didSet { needsLayout = true }
    }

    init(rowIndex: Int, columns: [SkeletonColumnDescriptor], appearance: SkeletonAppearance) {
        self.rowIndex = rowIndex
        self.columns = columns
        self.skeletonAppearance = appearance
        super.init(frame: .zero)
        rebuildPlaceholders()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    func update(columns: [SkeletonColumnDescriptor]) {
        self.columns = columns
        rebuildPlaceholders()
        needsLayout = true
    }

    func applyAppearance(_ appearance: SkeletonAppearance) {
        self.skeletonAppearance = appearance
        for (index, placeholder) in placeholders.enumerated() {
            guard index < columns.count else { break }
            let column = columns[index]
            placeholder.cornerRadius = column.style == .icon
                ? appearance.iconCornerRadius
                : appearance.textCornerRadius
            placeholder.applyAppearance(appearance)
        }
        needsLayout = true
    }

    private func rebuildPlaceholders() {
        placeholders.forEach { $0.removeFromSuperview() }
        placeholders = columns.map { column in
            let placeholder = SkeletonPlaceholderView()
            placeholder.cornerRadius = column.style == .icon
                ? skeletonAppearance.iconCornerRadius
                : skeletonAppearance.textCornerRadius
            placeholder.applyAppearance(skeletonAppearance)
            addSubview(placeholder)
            return placeholder
        }
    }

    override func layout() {
        super.layout()
        guard !columns.isEmpty, !placeholders.isEmpty else { return }

        let fractionRows = skeletonAppearance.textBarWidthFractions
        let fractionRow = fractionRows.isEmpty ? [] : fractionRows[rowIndex % fractionRows.count]

        for (columnIndex, column) in columns.enumerated() {
            let placeholder = placeholders[columnIndex]
            guard let columnFrame = columnFrames[column.identifier] else {
                placeholder.frame = .zero
                continue
            }

            switch column.style {
            case .icon:
                let iconSize = skeletonAppearance.iconSizeMode.size(forCellHeight: bounds.height)
                let centerX = columnFrame.minX + (columnFrame.width - iconSize) / 2
                let centerY = (bounds.height - iconSize) / 2 + skeletonAppearance.iconVerticalOffset
                placeholder.frame = .init(x: centerX, y: centerY, width: iconSize, height: iconSize)
            case .text:
                let barHeight = skeletonAppearance.textBarHeight
                let fraction = fractionRow.isEmpty ? 0.7 : fractionRow[columnIndex % fractionRow.count]
                let leadingInset = skeletonAppearance.textBarLeadingInset
                let trailingInset = skeletonAppearance.textBarTrailingInset
                let usableWidth = max(0, columnFrame.width - leadingInset - trailingInset)
                let barWidth = max(12, usableWidth * fraction)
                let barX: CGFloat = switch column.alignment {
                case .center:
                    columnFrame.minX + leadingInset + (usableWidth - barWidth) / 2
                case .right:
                    columnFrame.minX + columnFrame.width - trailingInset - barWidth
                default:
                    columnFrame.minX + leadingInset
                }
                let barY = (bounds.height - barHeight) / 2 + skeletonAppearance.textBarVerticalOffset
                placeholder.frame = .init(x: barX, y: barY, width: barWidth, height: barHeight)
            }
        }
    }

    func startAnimating() {
        // Stagger phases per row and per column so the highlight reads as a
        // diagonal wave instead of all bars pulsing in unison.
        let rowPhase = Double(rowIndex) * skeletonAppearance.shimmerRowStagger
        for (columnIndex, placeholder) in placeholders.enumerated() {
            let columnPhase = Double(columnIndex) * skeletonAppearance.shimmerColumnStagger
            placeholder.startAnimating(offset: -(rowPhase + columnPhase))
        }
    }

    func stopAnimating() {
        placeholders.forEach { $0.stopAnimating() }
    }
}

// MARK: - SkeletonPlaceholderView

/// A single rounded rectangle with a moving gradient highlight ("shimmer").
///
/// Uses the layer-backing `updateLayer` pattern: layer-only properties without
/// guard flags (cornerRadius, masksToBounds, backgroundColor in the absence of
/// `setBackgroundColor:`) would otherwise be overwritten by NSView's
/// ivar→layer sync. Setters mark `needsDisplay`; `updateLayer` is the single
/// place that pushes properties to the layer, inside the correct appearance
/// context.
final class SkeletonPlaceholderView: NSView {
    var cornerRadius: CGFloat = 4 {
        didSet {
            guard cornerRadius != oldValue else { return }
            needsDisplay = true
        }
    }

    private let gradientLayer = CAGradientLayer()
    private var baseColor: NSColor = .tertiaryLabelColor.withAlphaComponent(0.32)
    private var highlightColor: NSColor = .labelColor.withAlphaComponent(0.14)
    private var shimmerDuration: TimeInterval = 1.4

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        // clipsToBounds drives layer.masksToBounds via NSView's ivar pipeline,
        // so it survives `_updateLayerMasksToBoundsFromView` resyncs.
        clipsToBounds = true

        gradientLayer.locations = [0, 0.5, 1]
        gradientLayer.startPoint = .init(x: 0, y: 0.5)
        gradientLayer.endPoint = .init(x: 1, y: 0.5)
        // Suppress implicit animations on the gradient so frame changes during
        // layout don't trigger Core Animation cross-fades on top of the shimmer.
        gradientLayer.actions = [
            "position": NSNull(),
            "bounds": NSNull(),
            "frame": NSNull(),
            "locations": NSNull(),
            "contents": NSNull(),
        ]
        layer?.addSublayer(gradientLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }
    override var wantsUpdateLayer: Bool { true }

    override func layout() {
        super.layout()
        gradientLayer.frame = bounds
    }

    override func updateLayer() {
        // Single window where AppKit's ivar→layer sync has already run, so
        // re-applying these stays sticky until the next display cycle.
        layer?.cornerRadius = cornerRadius
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = baseColor.cgColor
            gradientLayer.colors = [
                NSColor.clear.cgColor,
                highlightColor.cgColor,
                NSColor.clear.cgColor,
            ]
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    func applyAppearance(_ appearance: SkeletonAppearance) {
        baseColor = appearance.baseColor
        highlightColor = appearance.highlightColor
        shimmerDuration = appearance.shimmerDuration
        needsDisplay = true

        // If a shimmer is currently running, restart it so the new duration
        // takes effect immediately rather than after the next stop/start cycle.
        if gradientLayer.animation(forKey: "shimmer") != nil {
            startAnimating()
        }
    }

    func startAnimating(offset: CFTimeInterval = 0) {
        let animation = CABasicAnimation(keyPath: "locations")
        animation.fromValue = [-1.0, -0.5, 0.0]
        animation.toValue = [1.0, 1.5, 2.0]
        animation.duration = shimmerDuration
        animation.repeatCount = .infinity
        // Negative offset advances the animation so each placeholder enters
        // at a different phase, producing a continuous wave effect.
        animation.beginTime = CACurrentMediaTime() + offset
        gradientLayer.add(animation, forKey: "shimmer")
    }

    func stopAnimating() {
        gradientLayer.removeAnimation(forKey: "shimmer")
    }
}

// MARK: - SkeletonBackgroundFillView

/// Opaque fill view used as the skeleton's underlying background. Uses
/// `updateLayer` so the backgroundColor is set inside the display cycle's
/// appearance context and isn't fighting any future ivar→layer resync.
private final class SkeletonBackgroundFillView: NSView {
    var backgroundColor: NSColor?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = backgroundColor?.cgColor
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}
