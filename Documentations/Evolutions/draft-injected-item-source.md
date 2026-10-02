# Draft - 由调用方提供清单的选择器

- **状态**: Accepted
- **创建日期**: 2026-10-02
- **最后更新**: 2026-10-02
- **实现分支**: `feature/injected-item-source`

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

### 二、公开边界往外挪一层

今天 `CLAUDE.md` 写的边界是「只有 `RunningPickerTabViewController` 对外，三个 picker 全
internal，消费者通过 tab VC 交互」。本次把它改成：

| 类型 | 原 | 新 |
|---|---|---|
| `RunningItemPickerViewController<Item>` | internal | **`public class`**（不是 `open`） |
| `RunningProcessPickerViewController` | internal | **`public final class`**，含 `Delegate` |
| `RunningProcess.init(...)` | internal | **public** |

三条都是为了同一件事：调用方要能**单独**呈现一个进程选择器（而不是那个双 tab 容器），并且
用自己的数据填充它。

**`public` 而不是 `open`**：外部不需要继承，需要的是能实例化。这个区别很值钱 ——
`open` 会把那 40 多个 subclass hook、`BaseConfiguration`、`PickerField` 全部拖进公开 API 并
永久背着；`public class` 下这些成员保持 internal，公开面只多出「初始化 + 代理 + 几个 AppKit
代理方法」。

`RunningProcess` 的 memberwise init 改 public，是为了让调用方能直接构造条目，**不必为「远端
进程」另造一个 `RunningItem` 实现**。它本来就是个纯数据结构，字段齐全（含 `platform`、
`architecture`），描述一个别处的进程和描述本机进程用同一个类型是合适的。

### 三、注入数据源后的进程选择器

`RunningProcessPickerViewController` 多一个初始化器。给了 source 就用 source，没给就还是本机枚举：

```swift
public init(configuration: Configuration = .init())                      // 本机，行为完全不变
public init(itemSource: any RunningItemSource<RunningProcess>, configuration: Configuration = .init())
public func reload()                                                      // 重新向 source 取一次
```

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

全部是新增与放宽（internal → public），**没有破坏性变更**。现有调用方只用
`RunningPickerTabViewController`，它的行为与签名一字未改。

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
| 2026-10-02 | 公开用 `public` 而非 `open`，并因此不必公开 40 多个 hook | 上游提案写的是「把泛型 picker 公开」。落地时发现这句有两种读法，代价差一个数量级：`open`（可被外部继承）要求每个 subclass hook、`BaseConfiguration`、`PickerField` 全部公开；`public`（只可实例化）则允许成员保持 internal。调用方要的是「实例化一个由我填数据的 picker」，不是继承，所以取后者。顺带解决了一个硬约束：公开的子类不允许有 internal 超类，所以 `RunningProcessPickerViewController` 要公开，基类必须跟着公开 —— 但只需公开到 `public`。 |
| 2026-10-02 | 不为「远端进程」另造 `RunningItem` 实现，改为公开 `RunningProcess.init` | 上游提案草拟了一个 `RuntimeRemoteRunningItem`。实现时发现没必要：`RunningProcess` 是纯数据结构，字段齐全，公开它的 memberwise init 就够了。少一个平行类型，而且表格列、角标、排序、右键菜单全部直接复用。 |
| 2026-10-02 | 变灰做在 row view 的 `alphaValue` 上，经 `didAdd:forRow:` | 每行只调一次。放在 cell 构造闭包里会在表格样式下每行每列各调一次 `shouldSelect`，而它通常是代理回调。已知局限：若某条目的可选性在**身份不变**的情况下改变（`RunningProcess` 的 `==` 只比 pid），diffable data source 不会重载该行，变灰会过期。实际不会发生 —— 可选性取决于 uid 与 pid，不会在会话中途变 —— 且既有的 `shouldSelectRow` 本来就有同样的性质。 |
| 2026-10-02 | 注入 source 时不轮询 | 本机枚举是本地增量刷新，几乎免费；注入的 source 一次可能是跨机器 RPC。按 `refreshInterval` 打一台手机是浪费，所以改为出现时取一次 + `reload()`，重取时机交给调用方。 |
| 2026-10-02 | 受限进程规则无条件生效 | 本库就是「挑一个条目去附加」，pid 0 / pid 1 在任何系统上都附加不了。加配置开关是为不存在的消费者提前付成本。 |
| 2026-10-02 | 不把本机两个数据源改造成 `RunningItemSource` 的实现 | 见「本次刻意不做的事」。简短版：增量刷新 vs 全量快照语义不合，换来的只有形式统一，而它恰好是唯一可能破坏本步验收标准（现有两个 tab 行为不变）的动作。 |
