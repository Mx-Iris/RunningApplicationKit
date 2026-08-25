# 呈现样式：实现说明

> 配套提案见 [选择器呈现样式（表格与列表）](../Evolutions/0002-picker-presentation-styles.md)。
> 本文记录**实际落地的实现**、与提案的差异，以及当前覆盖范围与已知降级。面向维护者。

## 背景与目标

两个标签页各自可选表格或列表呈现。完整动机见提案，这里只留一句结论：**表格里大量格子在重复
同一件事** —— 实测 400 个进程中 391 个平台是 `macOS`、只有 22 个在沙盒里、207 个没有架构值。

## 关键设计决策

### 列表仍然是 NSTableView，不是新控件

列表样式是**一个占满宽度的列 + 隐藏表头**，底下仍是同一个 `NSTableView` 和同一个
`NSTableViewDiffableDataSource`。

这样选中、type-select、右键菜单、骨架屏切换、快照 diff 全部原样复用，两种样式之间不存在
「这个功能只有表格有」的坑。代价是列表行的布局要塞进一个 cell view
（`ListRowTableCellView`）里，而不是用 `NSStackView` 自由排布。

替代方案是换 `NSCollectionView` 或自绘。否决理由：那要重新实现上面列的每一项能力。

### 样式默认值：公开类型不变，optional 只在内部

`rowHeight`、`cellSpacing`、`iconSize` 需要「没设过就跟着样式走，设过就听调用方的」。

直觉做法是把公开属性改成 optional —— **这会破坏读取端**。实际做法是公开属性保持非 optional 的
计算属性，背后存一个 optional：

```swift
private var explicitRowHeight: CGFloat?
public var rowHeight: CGFloat {
    get { explicitRowHeight ?? style.defaultRowHeight }
    set { explicitRowHeight = newValue }
}
```

三个好处：公开类型零变化；未设置的值在**运行时切换样式后会自动跟着变**；已设置的值不会被样式
悄悄覆盖。

### 弃用别名里唯一的真实约束：旧 init 的 `allowsColumns` 不能有默认值

旧 `init` 的参数原本全都有默认值。若原样保留，`ProcessConfiguration()` 会在新旧两个 init 之间
产生歧义，编译失败。

解法是**旧 init 里唯独 `allowsColumns` 不给默认值**，于是只有显式写出该标签才会匹配到它：

```swift
@available(*, deprecated, message: "Use init(style:…allowsFields:…) instead")
public init(
    title: String = "Running Processes",
    // …
    allowsColumns: [ProcessField],   // 没有默认值 —— 这正是消歧义的关键
    refreshInterval: TimeInterval = 2.0
)
```

**下次维护若有人"顺手"给它补一个默认值，所有无参构造会立刻编译失败。** 代码里有注释，这里再记
一次。

### 骨架屏：一个复合 cell，而不是两个列 cell

提案写的是「把两条文字条当两列解释」。落地时发现**不能真的当两列** ——
`SkeletonTableViewCoordinator` 按 `tableColumn.identifier` 查 `columns` 数组，而列表样式只有
一个真实列 `listRow`，喂两个虚拟列描述符会查不到、返回 `nil`、骨架直接不显示。

改成协调器多一个 `listRowLayout` 开关，命中时vends 一个复合的 `SkeletonListRowCellView`
（图标方块 + 两条文字条）。**两条文字条仍然按 `columnIndex` 0 / 1 去读 `SkeletonAppearance`**，
所以 `textBarWidthFractions`、`shimmerColumnStagger` 这些调参全部照用 —— 提案「不新增骨架屏
公开 API」的承诺守住了，只是内部实现方式和当初设想的不同。

### 列表行的字段分配写死在基类

`allowsFields` 决定显示哪些字段，但「哪些上标题行、哪些进副标题」是固定规则，写在
`RunningItemPickerViewController` 而不是各子类：

| 位置 | 字段 |
|---|---|
| 行首图标 | `icon` |
| 标题行 | `name` |
| 标题行右侧徽章 | `platform`、`sandboxed` |
| 副标题（`·` 分隔，按配置顺序） | 其余全部 |

子类只需覆盖 `fieldValue(_:for:)` 提供自己的字段取值（`executablePath` / `bundleIdentifier`），
排布逻辑不重复。

**徽章只在有信息时渲染**：平台是 `macOS` 不渲染，非沙盒不渲染。这是整个样式存在的理由 ——
表格列必须在每一行印一个值，徽章不必。

## 模块结构

```
Sources/RunningApplicationKit/
├── PickerPresentationStyle.swift    # Style 枚举与它的默认值（行高、间距、表头/排序控件可见性）
├── ListRowTableCellView.swift       # 列表行 cell：图标 + 标题 + 徽章 + 副标题；ListRowColumn.identifier
├── SkeletonListRowCellView.swift    # 列表行的骨架占位（图标方块 + 两条文字条）
├── DeprecatedNames.swift            # 弃用的 typealias，集中在此便于下个 minor 整文件删除
└── RunningItemPickerViewController.swift  # 样式分派、列表行组装、排序控件、运行时切换
```

## 核心算法与数据流

```
configureColumns(fields)
  ├─ 记录 configuredFieldIdentifiers 与 sortableFields（有 title 的才可排序）
  ├─ 移除所有既有列
  ├─ .table → 每个字段一列 + 每列一个骨架描述符
  └─ .list  → 一个 listRow 列 + skeletonCoordinator.listRowLayout
  └─ applyStyleToChrome()：表头显隐、排序控件显隐、搜索框在两行之间迁移

dataSource cell provider
  ├─ .list  → makeListRowCellView(item)  ← 组装规则集中在基类
  └─ .table → 子类的 makeCellView(for:item:)
```

运行时切换走 `applyStyleChange(baseConfiguration:reconfigureColumns:)`：先记下选中项，
重配 chrome 与列，`reloadData()` 后重新 apply 快照，再按 item 身份把选中项找回来并滚动到可见。
**不能用 diff 动画** —— cell view 的类型变了。

## 与提案的差异

| 差异 | 说明 |
|---|---|
| 骨架屏是**复合 cell**，不是两个列 cell | 提案设想把两条文字条当两列喂进现有模型。实际不行：协调器按列标识符查表，列表只有一个真实列。改为复合 cell，但两条文字条仍按 columnIndex 0/1 读外观参数，因此「不新增公开 API」的目标不变。 |
| 搜索框在列表样式下移到自己一行 | 提案只说「搜索框右侧放排序下拉」。落地时按预览的样子做成两行：标题行照旧，下面一行是占满宽度的搜索框 + 排序下拉。表格样式仍是标题行右侧的 300pt 搜索框。 |
| 新增 `setStyle(_:)` 便捷方法 | 提案只定了 per-tab 的 `style`。实际加了 `applicationStyle` / `processStyle` 两个属性外加一个同时设置两者的 `setStyle(_:)`，Example 的切换器用它。 |

## 验证

**单元测试**：`Tests/RunningApplicationKitTests/ConfigurationTests.swift`，与既有的 Mach-O 测试
一样只覆盖纯函数部分 —— 样式默认值、显式值覆盖、样式变更后未设置的值是否跟随、
`BaseConfiguration` 转发、字段可排序性、以及弃用别名的读写等价。

**这套测试里有一条是回归测试**：`initialSortField` 曾经在转换成 `BaseConfiguration` 时被整个
漏掉，编译完全正常、排序静默失效。变异验证过：把那两行转发删掉，三个断言立刻变红。

**结构验证**（一次性，不在套件里）：实例化 picker、放进窗口、逐个标签页切换样式，断言
列数（表格 6/7 列 → 列表 1 列）、列标识符、表头有无、行高（25 ↔ 44）、排序控件显隐、
排序菜单内容（不含 icon 那个空标题项）、以及切回表格后一切复原。**这条验证抓出了上面那个
漏传 bug** —— 单看编译和单元测试都发现不了。

**未做**：交互式 UI 验证。列表行的实际观感、徽章配色在深浅色下的表现、骨架屏动画，都需要人
运行 Example 用眼睛看。Example 里已经加好了 Table / List 切换器。

## 已知降级

- **切换样式时滚动位置只能尽力保持**。行高从 25 变 44（或反向），像素级还原没有意义；
  实现是把选中项滚回可见区域。没有选中项时回到列表顶部。
- **列表样式下没有列头排序指示器**。排序方向靠排序下拉按钮标题里的 ↑ / ↓ 表示。
- **切回表格样式时，列头不会显示当前排序的指示箭头**。排序本身是生效的，只是
  `NSTableView.sortDescriptors` 没有跟着回填。
- **`ListRowTableCellView` 的徽章每次配置都重建**。行内徽章最多两个，重建成本可忽略；
  若将来徽章变多需要改成复用。
- **列表样式忽略字段的 `preferredWidth` / `minWidth` / `maxWidth` / `headerAlignment`**。
  这些是表格专用概念，`PickerField` 协议仍然要求它们，列表分支只是不读。

## 后续工作

- `Style` 是枚举且已按可扩展方式实现，将来加 `.grid` 之类不需要动分派结构。
- 弃用别名（`DeprecatedNames.swift` 整个文件，加上两个 configuration 里的 `allowsColumns`
  属性与旧 init 重载）计划在下一个 minor 移除。

## 延伸阅读

- 配套提案：[选择器呈现样式（表格与列表）](../Evolutions/0002-picker-presentation-styles.md)
- 相关提案：[0001 - 进程平台识别与模拟器标记](../Evolutions/0001-simulator-platform-detection.md)
- 术语：[field 与 column、style](../Glossary.md)
