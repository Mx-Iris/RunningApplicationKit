# 0002 - 选择器呈现样式（表格与列表）

- **状态**: Implemented
- **作者**: JH
- **创建日期**: 2026-08-25
- **最后更新**: 2026-08-25
- **所属愿景**: 无
- **关联提案**: [0001 - 进程平台识别与模拟器标记](0001-simulator-platform-detection.md)
- **实现分支 / PR**: main
- **配套文档**: [呈现样式：实现说明](../Internal/PresentationStyles.md)

## 摘要

给两个选择器标签页各加一个 `style` 配置，取值 `.table`（现有的多列表格，保持默认）或
`.list`（单列、带副标题的行）。同时把 `allowsColumns` 与 `ProcessColumn` / `ApplicationColumn`
改名为样式无关的 `allowsFields` 与 `ProcessField` / `ApplicationField`，旧名全部保留弃用别名。
列表样式配一个排序下拉按钮，补上没有列头之后失去的排序入口。

## 动机

**表格里大量格子在重复同一件事。** 这不是观感判断，是可以数出来的。在开发机上做一次真实枚举
（400 个进程、21 个前台应用，全部经过库自己的判定逻辑）：

| 实测 | 表格里的后果 |
|---|---|
| **391 / 400** 进程的 platform 是 `macOS` | Platform 列 97.75% 的格子在刷同一个词 |
| **22 / 400** 进程真的在沙盒里 | Sandbox 列 378 个红叉是纯噪音，而红色是最强的视觉信号 |
| **207 / 400** 进程根本没有架构值 | Arch 列空白比有值还多，整列看着像坏了 |
| **2 种** 图标覆盖全部 400 个进程 | 图标列提供不了任何区分度 |

七列同时争宽度的直接代价是 Path 列只分到 300pt，**而路径最有信息量的是尾部**，恰恰先被截断 ——
用户要在 Processes 页找到模拟器里正在调试的那个进程时，看到的是
`…/RuntimeRoot/usr/libexec/logd`，得悬停 tooltip 才能确认。

Platform 列是 [0001](0001-simulator-platform-detection.md) 刚加的。当时的提问里已经把
「1384 行都写着 macOS」这个代价写进了选项，选择了完整措辞；实际跑起来看到效果后重新裁决，
结论是问题不在措辞长短，而在**这类字段根本不该占一整列**。

**参照实现**：Luma 的进程选择器（用户提供的截图）放弃了表格，改用「大图标 + 进程名 +
一行灰色副标题（PID · 完整路径）」的列表行。路径因此能占满整行，只在超长时中间省略。
代价是它**不显示架构、沙盒、平台中的任何一个**，也没有排序 —— 没有列头，这些字段既无处安放
也无法排序。而这三个字段正是本库与它的功能差异所在。

因此本提案不是把表格换成列表，而是**两者共存**：表格保留给要横向比较、要排序的场景，
列表给「搜一下、找到、选中」的场景。

## 前期调研

### 现状代码怎么走的

- `Sources/RunningApplicationKit/RunningPickerTabViewController.swift:24` / `:116` ——
  `public enum ApplicationColumn` / `ProcessColumn`，`allCases` 即两个 configuration 中
  `allowsColumns` 的默认值。
- `Sources/RunningApplicationKit/RunningItemPickerViewController.swift:3` ——
  internal `protocol PickerColumn`，提供 `title` / `preferredWidth` / `minWidth` / `maxWidth` /
  `headerAlignment`，全部是表格专用概念。
- `RunningItemPickerViewController.swift:400` / `:439` —— `makeSharedCellView` 与
  `compareSharedItems` 按列标识符分派。
- `RunningItemPickerViewController.swift:383` —— `addTableColumn(…)`，在 `title` 非空时挂上
  `NSSortDescriptor`，这是当前唯一的排序入口。
- `TableCellViews.swift` —— 每种列一个 cell view 子类，靠类身份复用。

### 骨架屏与「列」深度耦合 —— 这是本次工作量的主要来源之一

最近三个 commit 刚把骨架屏做成按列对齐的占位行，它的公开面就建立在列结构上：

- `SkeletonTableViewCoordinator` 持有 `[SkeletonColumnDescriptor]`，按 `tableColumn.identifier`
  查出列下标再生成占位（`SkeletonTableViewCoordinator.swift:11`、`:73-87`）。
- `SkeletonAppearance` 是 public struct，其中 `textBarWidthFractions` 是**行 × 列**的二维数组，
  另有 `shimmerColumnStagger` 按列错峰、`shimmerPhaseOffset(rowIndex:columnIndex:)`。

列表样式里没有「列」，但**行内确实有两条水平文字条**（标题、副标题）。已确认的做法是把这两条
当作两列喂进现有模型，因此**不新增任何骨架屏公开 API**，`shimmer` 那套调参全部照用。

### 原型验证：一个被推翻的判断

已产出可交互预览（用真实数据渲染，可在现状与新方案间原地切换）。它推翻了本提案作者先前的一个
判断：原本打算照 Luma 把图标统一放大到 32–40pt，**实测证明这只对一半场景成立** ——

- Applications 页：21 个应用 21 个独立图标，放大后确实成为扫视锚点。
- Processes 页：400 个进程只有 **2 种**图标，放大只是把重复放大。

结论是两个标签页在同一个 `.list` 样式下应当采用**不同的默认图标尺寸**，而不是统一。这也是
`style` 被放进各自 configuration、而非顶层的依据之一。

## 提议方案

1. 新增 `RunningPickerTabViewController.Style`，`.table` / `.list`，放进
   `ApplicationConfiguration` 与 `ProcessConfiguration` 各自的 `style` 属性，**默认 `.table`**。
2. `allowsColumns` → `allowsFields`；`ProcessColumn` / `ApplicationColumn` →
   `ProcessField` / `ApplicationField`；internal 的 `PickerColumn` → `PickerField`。
   旧名以属性转发、init 重载、`deprecated typealias` 三种形式全部保留。
3. 列表样式的行布局按**固定规则**由字段语义分配，不新增布局配置。
4. `rowHeight`、`cellSpacing`、图标尺寸改为「样式提供默认值，显式设置仍生效」，
   **公开属性类型不变**。
5. 列表样式在搜索框右侧提供排序下拉按钮；表格样式不提供（它有列头）。
6. 骨架屏复用现有协调器，列表样式下把标题条与副标题条当作两列。
7. `style` 支持运行时切换；Example 增加一个分段控件当场对比。

### 非目标

- **不删除、不弱化表格样式。** 它仍是默认，且是唯一支持按列横向比较与点击列头排序的样式。
- **不改变默认外观。** 现有调用方升级后视觉零变化。
- **不合并两个标签页。** Luma 是单一列表，本库保持 Applications / Processes 两页不变。
- **不做第三种样式**（网格等），但 `Style` 是枚举，留了扩展余地。
- **不做排序偏好持久化**，也不通过 delegate 回调用户改动的排序。
- **不提供列表行的自定义闭包**，行内布局由库决定。

## 详细设计

### Style

```swift
extension RunningPickerTabViewController {
    public enum Style: Hashable, Sendable, CaseIterable {
        /// Multi-column table. Sortable by clicking a column header.
        case table
        /// Single-column rows carrying a title and a subtitle.
        case list
    }
}
```

### 字段枚举改名

```swift
public enum ProcessField: String, CaseIterable, PickerField {
    case icon
    case name
    case pid
    case architecture
    case platform
    case sandboxed
    case executablePath
}

@available(*, deprecated, renamed: "ProcessField")
public typealias ProcessColumn = ProcessField
```

`ApplicationField` 同理。internal 的 `PickerColumn` 直接改名为 `PickerField`，不需要别名。
`PickerField` 上表格专用的 `preferredWidth` / `minWidth` / `maxWidth` / `headerAlignment`
保持原样 —— 列表样式不读它们。

### Configuration

以 `ProcessConfiguration` 为例，`ApplicationConfiguration` 同构：

```swift
public struct ProcessConfiguration {
    public var style: Style

    public var title: String
    public var description: String
    public var cancelButtonTitle: String
    public var confirmButtonTitle: String
    public var allowsFields: [ProcessField]
    public var refreshInterval: TimeInterval

    /// Initial sort. The user may change it at runtime; that change is not reported back.
    public var initialSortField: ProcessField?
    public var initialSortAscending: Bool

    // Style-defaulted values. The public type stays non-optional; the backing storage is
    // optional so that "never set" can fall back to the style's default, and so that
    // switching style at runtime moves an unset value along with it.
    private var explicitRowHeight: CGFloat?
    private var explicitCellSpacing: CGSize?
    private var explicitIconSize: CGFloat?

    public var rowHeight: CGFloat {
        get { explicitRowHeight ?? defaultRowHeight }
        set { explicitRowHeight = newValue }
    }

    public var cellSpacing: CGSize {
        get { explicitCellSpacing ?? defaultCellSpacing }
        set { explicitCellSpacing = newValue }
    }

    /// Icon edge length. Independent of `rowHeight` — in the table style icons track the
    /// row height, but a list row is tall enough that the two must be decoupled.
    public var iconSize: CGFloat {
        get { explicitIconSize ?? defaultIconSize }
        set { explicitIconSize = newValue }
    }

    private var defaultRowHeight: CGFloat {
        switch style {
        case .table: 25
        case .list: 44
        }
    }

    /// 22pt in the list: 400 processes resolve to only 2 distinct icons, so a larger icon
    /// magnifies repetition instead of aiding recognition. `ApplicationConfiguration`
    /// returns 34 here for the opposite reason.
    private var defaultIconSize: CGFloat {
        switch style {
        case .table: 20
        case .list: 22
        }
    }
}
```

**弃用别名**：

```swift
@available(*, deprecated, renamed: "allowsFields")
public var allowsColumns: [ProcessField] {
    get { allowsFields }
    set { allowsFields = newValue }
}
```

**init 的处理**是这套改名里唯一有真实约束的地方。旧 init 的所有参数都有默认值；若原样保留，
`ProcessConfiguration()` 会在新旧两个 init 之间产生歧义。做法是**旧 init 里 `allowsColumns`
不给默认值**，于是只有显式写出 `allowsColumns:` 标签时才会匹配到它：

```swift
public init(
    style: Style = .table,
    title: String = "Running Processes",
    // …
    allowsFields: [ProcessField] = ProcessField.allCases,
    initialSortField: ProcessField? = nil,
    initialSortAscending: Bool = true,
    refreshInterval: TimeInterval = 2.0
)

@available(*, deprecated, message: "Use init(style:title:…allowsFields:…) instead")
public init(
    title: String = "Running Processes",
    description: String = "Select a process",
    cancelButtonTitle: String = "Cancel",
    confirmButtonTitle: String = "Confirm",
    rowHeight: CGFloat = 25,
    cellSpacing: CGSize = .init(width: 0, height: 10),
    allowsColumns: [ProcessField],   // no default: this is what disambiguates the overload
    refreshInterval: TimeInterval = 2.0
)
```

### 列表行布局 —— 固定规则

字段按语义分配到三个位置，顺序由 `allowsFields` 决定：

| 位置 | 字段 |
|---|---|
| 行首图标 | `.icon` |
| 标题行 | `.name` |
| 标题行右侧标签 | `.platform`、`.sandboxed` |
| 副标题，`·` 分隔 | 其余全部（`.pid`、`.architecture`、`.executablePath`、`.bundleIdentifier`） |

`allowsFields` 里没有的字段一概不出现；`.icon` 缺席时行首不留位置。

标签**只在值得注意时渲染**，这是把整列噪音消掉的关键：

- `.platform` —— 平台是 `macOS` 时不渲染；模拟器平台用强调色，其它非 macOS 平台用中性色，
  判不出（`nil`）时渲染为一个提示未知的标签。
- `.sandboxed` —— 仅沙盒进程渲染一枚锁形图标，非沙盒不渲染。

路径用 `NSLineBreakMode.byTruncatingMiddle`，保住最有信息量的尾部。

### 排序控件

```swift
/// Shown in the list style only; the table style sorts by clicking a column header.
final class SortControl: NSPopUpButton { }
```

可选项从 `allowsFields` 中可排序的字段推导 —— 即 `compareSharedItems` / `compareItems` 能给出
非 `.orderedSame` 结果的那些，`.icon` 除外。选中当前项即翻转升降序，菜单项标题带方向箭头。
当前排序字段直接显示在按钮上，不点开也能看到。

### 骨架屏

`SkeletonTableViewCoordinator` 在列表样式下用两个虚拟列描述符（标题条、副标题条）加图标占位，
`SkeletonAppearance` 的 `textBarWidthFractions`、`shimmerColumnStagger` 等全部照用，
`columnIndex` 取 0 / 1。**公开 API 不变。**

### 运行时切换

`style` 变化时重建列与 cell view，并保留：选中项（按 `processIdentifier` 重新定位）、
搜索文本、排序状态、滚动位置（尽力而为 —— 行高变化后无法精确还原，按选中项回滚）。

## 替代方案考量

**直接把表格换成列表。** 预览做出来之后最自然的想法。**被明确否决** —— 表格是唯一支持横向
比较与点击列头排序的呈现，且列表放弃了架构、沙盒、平台的独立可视位置。

**`allowsColumns` 在列表下复用为「副标题显示哪些字段」，名字不动。** 这是本提案最初的推荐方案。
否决理由：名字里的 "Columns" 在没有列的样式下自相矛盾，等于把一处命名债务永久固化。改名 +
弃用别名的代价只有一次。

**列表样式忽略 `allowsColumns`，字段固定。** 实现最省事，否决理由是它制造「配了没反应」的坑，
而这类坑编译器不会警告。

**给列表单开一组 `listFields` 配置。** 语义最清晰，否决理由是两组配置必然走岸，且调用方要维护
两份字段清单。

**`style` 放顶层 `Configuration`，一个管两个标签页。** 否决理由见前期调研：实测证明两个标签页
在图标尺寸上就该取不同默认值，一个开关管两页会强行抹平这个差异。

**顶层给默认值 + per-tab 覆盖的两层结构。** 最灵活，否决理由是多一层公开 API，且「覆盖」语义
需要额外解释（传 `nil` 还是传值？）。

**默认改成 `.list`。** 新用户直接得到更好的默认。否决理由：所有现有调用方升级后界面突变，
而这**不是编译错误、是静默的外观改变**，比 0001 那次「多一列」影响大得多。

**列表样式不支持排序 / 用一排可点标签 / 两种样式都显示排序下拉。** 分别否决：不支持排序会让
两种样式能力不对等；可点标签占一整行且字段一多就挤；两种样式都显示会在已有标题、副标题、
搜索框的表格头部再塞一个冗余控件。

**为列表新增 `ListSkeletonAppearance`。** 否决理由：列表行的两条文字条恰好套得进现有的行 × 列
模型，新增一组公开 API 只会让两套调参走岸。

**列表样式忽略 `rowHeight` 等既有配置。** 否决理由与否决「忽略 `allowsColumns`」完全相同 ——
又一个「配了没用」。

**行内容交给调用方闭包。** 否决理由：公开 API 大一圈，且默认外观仍需另外提供一套，
否则开箱就是空白行。

**图标尺寸统一默认值 / 完全不开放。** 否决理由：统一则两页必有一页不对（实测依据见前期调研）；
不开放则调用方只能改行高去间接影响它。

**`style` 只能在初始化时确定。** 实现简单得多。否决理由是无法当场对比两种样式，
且断了将来做「记住用户偏好」的路。

**跳 0.3.0 直接移除旧名 / 弃用期保留到 1.0。** 前者让刚确定的弃用别名白做且下游升级即断；
后者让双套命名在仓库里长期共存，新人读代码时不知道该用哪个。

## 影响

### 源码兼容性（source compatibility）

**纯新增 + 全量弃用别名，实际破坏面为零。**

- **纯新增**：`Style`、`style`、`allowsFields`、`ProcessField` / `ApplicationField`、
  `initialSortField`、`initialSortAscending`、`iconSize`。
- **改名但留别名**：
  | 旧名 | 新名 | 别名形式 |
  |---|---|---|
  | `allowsColumns` | `allowsFields` | `@available(*, deprecated, renamed:)` 计算属性转发 |
  | `ProcessColumn` / `ApplicationColumn` | `ProcessField` / `ApplicationField` | `deprecated typealias` |
  | `init(…allowsColumns:…)` | `init(…allowsFields:…)` | 保留一个重载，靠 `allowsColumns` 无默认值消歧义 |

  现有调用方**一行不改即可编译**，只会拿到弃用警告与 Xcode 的一键修复。
- **类型不变**：`rowHeight` / `cellSpacing` 的公开类型仍是 `CGFloat` / `CGSize`，
  optional 只存在于内部存储。读写两侧都不受影响。
- **默认外观不变**：`style` 默认 `.table`，`rowHeight` 在 `.table` 下仍回落到 25。
- 对 `ProcessColumn` 做穷尽 `switch` 的外部代码不受影响 —— 枚举 case 没有增删，且其成员
  （`title` 等）均为 internal。

### ABI 兼容性

不适用 —— 本库以 SPM 源码分发，使用方每次重新编译。`Package.swift` 未开启
`-enable-library-evolution`，也不以 `binaryTarget` 分发。

### 下游影响

- 本仓库内：`RunningApplicationKit` 与 `Example`（后者要加样式切换控件）。
- 测试 target 不受影响 —— 现有 34 个测试全部针对 Mach-O 解析，与 UI 无关。
- 跨仓库：本库公开分发，下游消费者未知。**弃用警告会出现在所有使用 `allowsColumns` 或
  `ProcessColumn` 的下游代码里**，需要写进 release notes。

### 文档与示例

- `README.md`：配置示例中的 `allowsColumns` 需改为 `allowsFields`，并补充 `style` 与列表样式。
- `Documentations/Internal/`：列表样式的行布局规则、骨架屏的两列映射，值得一篇实现说明。
- `Example/`：增加样式切换分段控件。

## API 演进与废弃策略

- **弃用而非删除**：`allowsColumns`、`ProcessColumn`、`ApplicationColumn` 及旧 init 重载全部标注
  `@available(*, deprecated, renamed:)`，尽可能提供一键修复。
- **移除时机**：下一个 minor 版本移除，届时在 release notes 中点名。
- **不需要 semver major 跃迁**：本次实际破坏面为零。库当前在 0.2.x，按 minor 发布。
  release notes 需同时点名两件事：新增 `.list` 样式（默认不启用），以及旧命名进入弃用期。

## 落地步骤

1. **`Style` 枚举与 configuration 改造** —— 新增 `style`、样式默认值机制（内部 optional +
   回落）、`initialSortField` / `initialSortAscending`、`iconSize`。可独立编译。
2. **改名与弃用别名** —— `allowsFields`、`ProcessField` / `ApplicationField`、`PickerField`，
   连同三种别名形式。此步完成后现有调用方与 Example 应当**零改动通过编译**，仅有弃用警告，
   这本身就是该步的验收标准。
3. **列表 cell view** —— 行内布局的固定规则、平台与沙盒标签、路径中间省略。
4. **表格 / 列表分派** —— `configureColumns`、`makeCellView`、行高与图标尺寸走样式默认值。
5. **排序控件** —— 列表样式下的 `NSPopUpButton`，可选项从 `allowsFields` 推导，
   接上 `initialSortField`。
6. **骨架屏适配** —— 列表样式下的两列映射，确认 `SkeletonAppearance` 公开面未变。
7. **运行时切换** —— 重建列与 cell，保留选中项、搜索文本、排序与滚动位置。
8. **Example 与文档** —— 分段控件、README、实现说明。

**收尾时必须判断两件事**（判断结果写进决策日志，不允许沉默跳过）：

- **要不要配套专题文章** —— 候选是一篇实现说明（列表行布局规则、骨架屏两列映射、
  运行时切换的状态迁移），以及一篇使用指南（两种样式各自适合什么场景、`allowsFields`
  在两种样式下的不同效果 —— 这是从 API 签名看不出来的契约）。
- **有没有引入新术语** —— `field`（取代 `column`）、`style` 两个候选待评估，
  它们与既有术语的关系需要在术语表里说清。

## 决策日志

| 日期 | 变更 | 说明 |
|------|------|------|
| 2026-08-25 | Created as Draft | 用户看到 0001 落地后的实际界面，判断「UI 太丑」，并以 Luma 的进程选择器截图作为参照方向。经四轮澄清提问后成文。 |
| 2026-08-25 | 定总体：两种样式共存 | 用户原话「保留原实现，新 UI 根据 Style 枚举展示」。否决「直接把表格换成列表」—— 表格是唯一支持横向比较与列头排序的呈现。 |
| 2026-08-25 | 定作用域：style 进各 tab 的 configuration | 否决「放顶层一个管两页」（抹平了两页在图标尺寸上的实测差异）、「顶层默认 + per-tab 覆盖」（多一层 API 且覆盖语义需额外解释）。 |
| 2026-08-25 | 定默认：`.table` | 否决「默认 `.list`」—— 那是静默的外观突变，比 0001 那次多一列影响大得多。也否决「两页各取更合适的默认」以免默认值不一致。 |
| 2026-08-25 | 定命名：改名 + 全量弃用别名 | **用户选择了提问选项之外的方向**：不复用 `allowsColumns` 的旧名，而是改名并弃用旧的。据此否决原推荐的「复用旧名」、以及「忽略」「新增独立配置」两案。 |
| 2026-08-25 | 定 Style case：`.table` / `.list` | 否决 `.compact` / `.comfortable`（不看文档猜不出长什么样）、`.columns` / `.rows`（两者都由行构成，区分度不够）。 |
| 2026-08-25 | 定弃用范围：属性 + init + 枚举全留别名 | 否决「只弃用属性、init 参数直接改名」（init 恰是最常见用法，弃用期形同虚设）、「不留弃用期」（距上次发布仅隔一次改动）。 |
| 2026-08-25 | 定排序：列表样式下的下拉按钮 | 否决「不支持排序」（两种样式能力不对等）、「一排可点标签」（占一整行且字段多了会挤）、「两种样式都显示」（表格头部已有标题、副标题、搜索框）。 |
| 2026-08-25 | 定骨架屏：复用现有，两条文字当两列 | 否决「新增 `ListSkeletonAppearance`」（两套调参必然走岸）、「列表样式不做骨架屏」（刚做完的能力直接退化）。 |
| 2026-08-25 | 定既有配置：样式给默认值，显式设置仍生效 | 否决「列表样式忽略这些配置」—— 与否决「忽略 `allowsColumns`」同一个理由，都是「配了没用」。实现上公开类型保持非 optional，optional 只存在于内部存储。 |
| 2026-08-25 | 定行内布局：固定规则 | 否决「额外配一个哪些上标题行」（能配出很难看的组合）、「交给调用方闭包」（公开 API 大一圈且默认外观仍需另供）。 |
| 2026-08-25 | 定图标尺寸：两页各自默认，可覆盖 | 依据实测：应用页 21/21 独立图标、进程页 400 个仅 2 种。否决「统一默认」（必有一页不对）、「完全不开放」（只能靠改行高间接影响）。 |
| 2026-08-25 | 定运行时切换：支持，Example 加分段控件 | 否决「只能初始化时定」—— 无法当场对比两种样式，也断了将来做偏好记忆的路。 |
| 2026-08-25 | 定排序状态：可预设初始值，不回调 | 否决「预设 + delegate 回调」（该协议已有七个方法）、「什么都不提供」（连默认排序都满足不了）。 |
| 2026-08-25 | 定版本策略：保留到下一个 minor，不跳 major | 否决「跳 0.3.0 直接移除」（弃用别名白做且下游即断）、「保留到 1.0」（双套命名长期共存令人困惑）。 |
| 2026-08-25 | 原型推翻了一个自有判断 | 原打算照 Luma 把图标统一放大到 32–40pt。真实数据显示 Processes 页 400 个进程只有 2 种图标，放大只是放大重复。据此改为两页各自默认，并成为 style 放进各 tab configuration 的依据之一。 |
| 2026-08-25 | Draft → Accepted | 用户审阅后批准（原话「开工」），实现开始。 |
| 2026-08-25 | Accepted → Implemented | 八个落地步骤全部完成。库、测试、Example 均构建通过；46 个单元测试通过（以 `swift test` 退出码为准）。第 2 步的验收标准达成：模拟旧调用方的代码零改动编译，每处旧名各产生一条弃用警告，`ProcessConfiguration()` 无歧义。 |
| 2026-08-25 | 落地时发现并修复一个静默失效 | `initialSortField` 在转换成 `BaseConfiguration` 时被整个漏掉 —— 编译正常、单元测试当时也没覆盖，配置的初始排序完全不生效。由一次性的结构验证（实例化 picker、逐标签页切换样式、断言列数/表头/行高/排序菜单）抓到。已补回归测试并做变异验证：删掉转发那两行，三个断言立刻变红。 |
| 2026-08-25 | 收尾判断一：写配套实现说明 | 判定**需要**。三条代码里看不出来的信息：旧 init 的 `allowsColumns` 为什么不能有默认值（补上默认值会让所有无参构造编译失败）、骨架屏为什么没能按提案设想的「两条文字条当两列」实现、以及样式默认值为什么用内部 optional 而非公开 optional。已写入 `Documentations/Internal/PresentationStyles.md`。 |
| 2026-08-25 | 收尾判断二：登记新术语 | 判定**需要**。`field` 与 `column` 的分野是这次改名的全部理由，`style` 则容易与 `NSTableView.style` 混淆，两条均已登记进项目术语表。无需登记全局术语。 |
| 2026-08-25 | 实现与提案的三处差异 | 骨架屏改用复合 cell（协调器按列标识符查表，列表只有一个真实列）；搜索框在列表样式下移到自己一行；新增 `setStyle(_:)` 便捷方法。逐条记在实现说明的「与提案的差异」一节，提案正文保持原貌。 |
| 2026-08-26 | 分配编号 0002 | 落地 commit 中取号：fetch 全部共享分支后，已编号提案的全局最大值为 0001，故取 0002，由 `draft-picker-presentation-styles.md` 改名而来。 |
