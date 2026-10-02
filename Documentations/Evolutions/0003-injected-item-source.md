# 0003 - 由调用方提供清单的选择器

- **状态**: Implemented
- **创建日期**: 2026-10-02
- **最后更新**: 2026-10-02
- **实现分支**: `feature/injected-item-source`（已合入 `main`，发版 `0.7.0`）
- **配套文档**: 无（理由见决策日志末行）；术语见[术语表 item source](../Glossary.md#item-source条目供给源)

## 摘要

让调用方能把**自己手上的一批条目**交给选择器显示，而不是只能显示本机枚举出来的应用与进程。
动因来自下游 RuntimeViewer：它要在一台 iOS 设备上挑进程注入，那台设备的进程表本库看不见、
也不该由本库去取。

同批加两件与之配套的小改动：**选不中的行要看起来选不中**（`shouldSelect(item:)` 返 `false`
目前只是选不中，行渲染毫无变化），以及 **`kernel_task` / `launchd` 这类进程默认不可选中**
（本库现在对它们没有任何处理，本机选择器今天可以选中它们、然后让调用方的 attach 失败）。

本提案的设计决定**不是在本仓库做出的**：它们是 RuntimeViewer 那份提案
`draft-jailbroken-ios-injection.md` 在两轮澄清提问里与用户定下的，本文件记录落到本库的那一份，
并把「实现时发现与当初设想不符」的几处如实记下。

## 方案

### 一、`RunningItemSource`

```swift
/// 选择器的条目从哪来。
public protocol RunningItemSource<Item>: Sendable {
    associatedtype Item: RunningItem
    /// 取一次完整快照。
    func loadItems() async throws -> [Item]
}
```

### 二、公开边界原地不动，新能力加在既有门面上

本节与提案最初写的方案**相反**，改写自实现中的失败结果，见决策日志
「公开 picker 类的尝试已撤回」一行。

最初的方案是把边界往外挪：让 `RunningItemPickerViewController<Item>` 与
`RunningProcessPickerViewController` 从 internal 变成 `public`，好让调用方单独实例化一个进程
选择器。**这条路编不过，已撤回。** 边界因此保持 `CLAUDE.md` 原本写的那一条：只有
`RunningPickerTabViewController` 对外，三个 picker 全 internal。

唯一一处放宽的是数据结构：

| 类型 | 原 | 新 |
|---|---|---|
| `RunningProcess.init(...)` | internal | **public** |

`RunningProcess` 的 memberwise init 改 public，是为了让调用方能直接构造条目，**不必为「远端
进程」另造一个 `RunningItem` 实现**。它本来就是个纯数据结构，字段齐全（含 `platform`、
`architecture`），描述一个别处的进程和描述本机进程用同一个类型是合适的。

### 三、注入数据源后的进程选择器

`RunningProcessPickerViewController` 多一个初始化器。给了 source 就用 source，没给就还是本机
枚举 —— 但它**和这个类一样是 internal 的**，调用方碰不到：

```swift
init(configuration: Configuration = .init())                      // 本机，行为完全不变
init(itemSource: AnyRunningItemSource<RunningProcess>, configuration: Configuration = .init())
func reload()                                                     // 重新向 source 取一次
```

公开入口在门面上，三样一起用：

```swift
public init(
    configuration: Configuration = .init(),                       // .init(tabs: [.processes]) 去掉 tab 栏
    applicationConfiguration: ApplicationConfiguration = .init(),
    processConfiguration: ProcessConfiguration = .init(),
    processItemSource: AnyRunningItemSource<RunningProcess>? = nil
)
public func reloadProcesses()
```

参数类型是具体的 `AnyRunningItemSource<RunningProcess>`，不是 `any RunningItemSource<RunningProcess>`：
受约束关联类型的存在类型要 macOS 13 的运行时支持，本库部署到 11。这不是风格取舍，是实测的编译
错误。

注入 source 时的两处刻意差异：

- **不轮询。** 本机那条路每 `refreshInterval` 增量刷新一次；注入的 source 每次 `loadItems()`
  可能是一次跨机器 RPC，按 2 秒打一台手机是浪费。改为出现时取一次 + 暴露 `reload()`，什么时候
  重取由调用方决定。
- **首次加载期间显示骨架屏**（基类已有 `setSkeletonVisible`），因为远端取数有可见延迟，而本机
  枚举没有。

### 四、选不中的行要看起来选不中

基类在 `tableView(_:didAdd:forRow:)` 里按 `shouldSelect(item:)` 调整 row view 的
`alphaValue`。选这个钩子而不是在 cell 构造闭包里做，是因为它**每行只调用一次**；cell 闭包在
表格样式下每行要走一遍每一列，`shouldSelect` 又常常是一次代理回调。

两种呈现样式自动都对 —— 变灰作用在 row view 上，不在 cell 上。

### 五、特殊进程默认不可选中

```swift
/// 任何东西都不该尝试附加的进程。
public enum RestrictedProcess {
    public static func isRestricted(processIdentifier: pid_t) -> Bool  // pid 0 与 pid 1
}
```

基类的 `tableView(_:shouldSelectRow:)` 先问这条规则，再问 `shouldSelect(item:)`。无条件生效、
不加配置开关：本库的用途是「挑一个运行中的条目去附加」，而这两个 pid 在任何系统上都附加不了，
为一个不存在的消费者提前加开关不值得。

### 六、本次刻意**不**做的事

- **不把本机那两个数据源改造成 `RunningItemSource` 的实现。** RuntimeViewer 那份提案原话是
  「现有的两种来源各自成为它的实现」。实现时判断这条不该照做：进程选择器的刷新是**增量**的
  （diff 新增/消失的 pid，避免每 2 秒重建四百个 `RunningProcess`），而 `loadItems() async
  throws -> [Item]` 是全量快照语义，套上去等于把一条调过的性能路径换掉，换来的只有形式统一。
  而且那份提案给本步定的验收标准正是「现有两个 tab 除特殊进程变灰外行为不变」—— 改造它恰好是
  唯一可能破坏该标准的动作。
- **不动模型层**（`icon` 保持 `NSImage?`）、**不动 AppKit UI**、**不拆平台中立 core**。这三条
  是上游提案里用户明确否决过的方向。

## 影响

### API 兼容

全部是新增，外加一处放宽（`RunningProcess` 的 memberwise init，internal → public），
**没有破坏性变更**。现有调用方只用 `RunningPickerTabViewController`，它既有的签名一字未改 ——
新增的两个参数（`configuration.tabs`、`processItemSource:`）都有默认值，默认值即旧行为。

`Delegate` 多了一条要求 `didFailToLoadProcesses`，但它在 `public extension` 里带默认实现，
所以仓库外的实现方也不必改。

唯一的行为变化：`kernel_task` 与 `launchd` 在本机进程选择器里变成不可选中且变灰。这是有意的 ——
它们原本可选，选了之后附加必然失败。

### 版本

次版本号即可（新增 API + 一处有意的行为收紧）。下游 RuntimeViewer 需要本库发版后抬 pin。

### 测试

按本仓库既有做法：不读真实进程、不依赖运行机器。新增一个假的 `RunningItemSource`，picker 托在
真实 `NSWindow` 里（`PickerStructureTests` 的做法 —— 给游离视图赋 frame 会让 AppKit 顺手做
autoresizing，恰好掩盖这类布局/接线缺陷）。

覆盖：注入 source 后显示的是 source 给的条目、不碰本机进程表；`reload()` 会重取；受限 pid 与
代理判否的行都变灰且选不中；代理放行的行正常。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-10-02 | Created as Accepted | 设计决定在下游 RuntimeViewer 的提案 `draft-jailbroken-ios-injection.md` 里已与用户经两轮澄清提问定稿（「抽象只做数据源」「picker 整体切换」「特殊进程显示但不可选中」），用户随后批准按该计划实施。本文件是那份决定落到本库的记录，不重新开一轮提问 —— 重问等于把已定的事再议一遍。 |
| 2026-10-02 | **公开 picker 类的尝试已撤回**，picker 保持 internal，新能力加在 `RunningPickerTabViewController` 门面上 | 上游提案写的是「把泛型 picker 公开」，本提案原先的「方案 二」照此写了一张 internal → public 的表。**实到实处编不过，整条路撤回。** 我原以为 Swift 允许 `override` 的访问级别低于所在类型；它不允许：`overriding instance method must be as accessible as its enclosing type`（5 处）、`must be declared public because it matches a requirement in public protocol 'Delegate'`（4 处），再加「公开类不得有 internal 超类」会把基类一起拖进来。要编过就得把那 40 多个 subclass hook、`BaseConfiguration`、`PickerField` 全部公开，并且让 `didConfirm(item:)` 和 `loadItems()` 变成外部可调 —— 外人能在 picker 背后直接触发代理回调。代价远超「能单独实例化一个 picker」这点收益，而本库早就有现成的门面模式能达到同样目的。方案 二、三已按实际落地改写。 |
| 2026-10-02 | 不为「远端进程」另造 `RunningItem` 实现，改为公开 `RunningProcess.init` | 上游提案草拟了一个 `RuntimeRemoteRunningItem`。实现时发现没必要：`RunningProcess` 是纯数据结构，字段齐全，公开它的 memberwise init 就够了。少一个平行类型，而且表格列、角标、排序、右键菜单全部直接复用。 |
| 2026-10-02 | 变灰做在 row view 的 `alphaValue` 上，经 `didAdd:forRow:` | 每行只调一次。放在 cell 构造闭包里会在表格样式下每行每列各调一次 `shouldSelect`，而它通常是代理回调。已知局限：若某条目的可选性在**身份不变**的情况下改变（`RunningProcess` 的 `==` 只比 pid），diffable data source 不会重载该行，变灰会过期。实际不会发生 —— 可选性取决于 uid 与 pid，不会在会话中途变 —— 且既有的 `shouldSelectRow` 本来就有同样的性质。 |
| 2026-10-02 | 注入 source 时不轮询 | 本机枚举是本地增量刷新，几乎免费；注入的 source 一次可能是跨机器 RPC。按 `refreshInterval` 打一台手机是浪费，所以改为出现时取一次 + `reload()`，重取时机交给调用方。 |
| 2026-10-02 | 受限进程规则无条件生效 | 本库就是「挑一个条目去附加」，pid 0 / pid 1 在任何系统上都附加不了。加配置开关是为不存在的消费者提前付成本。 |
| 2026-10-02 | 不把本机两个数据源改造成 `RunningItemSource` 的实现 | 见「本次刻意不做的事」。简短版：增量刷新 vs 全量快照语义不合，换来的只有形式统一，而它恰好是唯一可能破坏本步验收标准（现有两个 tab 行为不变）的动作。 |
| 2026-10-02 | 存的是具体的 `AnyRunningItemSource<Item>`，不是 `any RunningItemSource<Item>` | 协议声明了 primary associated type，所以写参数化存在类型是自然的写法 —— 但它编不过：`runtime support for parameterized protocol types is only available in macOS 13.0.0 or newer`，本库部署到 macOS 11。于是自己写一个类型擦除壳。顺带的好处是闭包初始化器，调用方「从别处取一个清单」通常不值得为它命名一个类型。 |
| 2026-10-02 | 单 tab 时直接托管那个 picker，不走 `NSTabViewController` | 只有一项的 `NSTabViewController` 会画出一段式的 tab 控件，看起来像坏掉的 tab 栏，而不像标题。`Configuration.tabs` 只有一项时跳过容器，tab 栏随之消失。 |
| 2026-10-02 | 落地为 0003，状态置 Implemented；**不写配套实现说明**；术语表加一条 | 配套文档：本库既有两篇 `Internal/` 说明都是为「跨多个文件、需要实测表格」的主题写的（平台识别的 slice 四级回退、呈现样式的默认值交互）。本次两处值得记的实现事实 —— macOS 11 的存在类型下限、单 tab 不走容器 —— 各自只约束一行代码，注释就写在那一行的声明上，维护者改到那里必然看见；另起一篇等于立刻多一份会漂移的副本。术语表：新增 `item source` 一条，因为「本机枚举算不算一个 source」是这次最容易误会的点（答案是不算，见「本次刻意不做的事」）。 |
