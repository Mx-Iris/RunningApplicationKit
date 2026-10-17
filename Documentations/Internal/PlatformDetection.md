# 平台识别：实现说明

> 配套提案有两份：[进程平台识别与模拟器标记](../Evolutions/0001-simulator-platform-detection.md)定下要识别平台以及 `Platform` 的形状；[接入 swift-proc](../Evolutions/draft-adopt-swift-proc.md)把数据来源从读可执行文件换成问内核。
> 本文记录**当前的实现**、为什么这样做、被替换的旧方案，以及已知降级。面向维护者。

## 背景与目标

判断一个进程属于哪个平台，核心用途是把模拟器里运行的进程从宿主进程里分辨出来。完整动机见 0001。

这里只需要记住一件事：**架构判不出模拟器**。Apple Silicon 上 iOS 模拟器里的进程跑的是原生 arm64 代码，`PROC_PIDARCHINFO` 返回的 `CPU_TYPE_ARM64` 与宿主进程一模一样。

## 关键设计决策

### 平台问内核 —— 0001 的「内核问不到」不成立

0001 认定内核不提供平台，依据是一次扫描：用 8 字节缓冲区逐个试 `proc_pidinfo` 的 flavor 1–64，只有 1、6、19、28、32、34 有返回。这个结论是错的。xnu 从 macOS 10.15（xnu-6153）起就有私有 flavor `PROC_PIDPLATFORMINFO`（30）：

- 它返回 4 字节的 `uint32_t`。`proc_pidinfo_internal` 只在缓冲区**小于**所需大小时报错，8 字节能通过，所以扫描本该看到它；推测当时只把返回 8 字节的算作「有返回」。
- `proc_info.c` 把它列在免同用户检查的 flavor 里（`NO_CHECK_SAME_USER`），也会去找 zombie，所以任何调用方都能查任何用户的进程。`PROC_PIDARCHINFO` 没有这项豁免。
- 内核在 exec 时从**实际加载的那个切片**读 `LC_BUILD_VERSION`，没有时读旧式的 `LC_VERSION_MIN_*`（mach_loader.c），再由 kern_exec.c 的 `proc_setplatformdata` 记到进程上；fork 出的子进程继承父进程的值。这正是 0001 想回答的「这个二进制被编译给哪个平台」。

调用走 swift-proc 私有模块的 `ProcessIdentifier.platform()`，包装在 `BSDProcess.platform(for:)` 里。代价是依赖 SDK 没有声明的接口，好在它从 macOS 10.15 起没有变过。

### 内核值 0 映射为 `nil`

内核没有记下平台时报 0（`PLATFORM_UNKNOWN`）。`BSDProcess.platform(kernelValue:)` 把 0 映射为 `nil`，其余值交给 `Platform(machOPlatformValue:)`，所以表外的新平台仍保留为 `.unknown(原始值)`。

### 每次按进程查，不缓存

一次查询就是一次系统调用，所以 `RunningProcessEnumerator` 与 `RunningApplication` 都按进程号直接问，不再按可执行文件路径缓存。两个附带的好处：

- 不需要路径。`RunningApplication` 以前要靠 `NSRunningApplication.executableURL` 才能读文件，没有这个值的应用（例如不在 app bundle 里的进程）平台一直是 `nil`。
- 不会张冠李戴。同一个路径上的文件被替换后，旧缓存不会失效；按进程问没有这个问题。

### 不按路径前缀判定

模拟器 guest 进程（运行在模拟器沙盒内部的进程，见[术语表](../Glossary.md#guest-进程)）的可执行文件都在 `/Library/Developer/CoreSimulator/…/RuntimeRoot/` 之下，按前缀匹配看上去最省事。否掉的理由有两条，第二条是决定性的：

1. 它依赖 Apple 的目录约定而非 ABI 字段，路径一改即失效。
2. **它只能回答「是不是模拟器」**，给不出 Mac Catalyst、DriverKit、iPad app on Mac。公开 API 是通用的 `Platform` 枚举，路径判定支撑不了。

### `unknown` 携带原始数值，与 `Architecture` 不对称

`Architecture.unknown` 不带值，`Platform.unknown` 带。CPU 类型表几十年不变，而 Mach-O 的 platform 表几乎每年增长：写这段代码时 SDK 已经定义到 24。带上原始值，遇到第 25 个平台时至少还能显示成 `Platform 25`。代价是 `Platform` 不能自动合成 `RawRepresentable`，双向转换靠手写的 `init(machOPlatformValue:)` 与 `machOPlatformValue`。

### 协议 requirement 给默认实现

`RunningItem` 是 public 协议，加 requirement 本是源码破坏性变更。在协议扩展里给 `var platform: Platform? { nil }`，把破坏面降到零。代价是库外的实现者会静默拿到 `nil`。

## 模块结构

```
Sources/RunningApplicationKit/
├── Platform.swift     # 枚举：24 个 Mach-O 平台 + unknown(UInt32)，及其显示、排序、搜索事实
└── BSDProcess.swift   # platform(for:) 问内核；platform(kernelValue:) 映射内核的值
```

`Platform` 的四个静态事实（Mach-O 常量、显示文本、case 名、排序序号）由一个 switch 统一给出（`Platform.facts`），新增 case 时编译器会强制一次补齐。

## 数据流

```
RunningProcessEnumerator.makeProcess(for:) / RunningApplication.init(from:)
  └─ BSDProcess.platform(for: pid)
       └─ swift-proc: ProcessIdentifier(rawValue: pid).platform()
            └─ proc_pidinfo(pid, PROC_PIDPLATFORMINFO = 30) → uint32_t
       └─ platform(kernelValue:) → nil（0）或 Platform(machOPlatformValue:)
```

## 被替换的方案：读可执行文件的 Mach-O 头（0.7.0 及以前）

0001 落地时，`MachOPlatform.swift` 用 `proc_pidpath` 拿路径，打开文件读 `LC_BUILD_VERSION`。胖二进制要先挑切片，而挑切片要知道进程的运行架构，`PROC_PIDARCHINFO` 却对 279 个进程不可用（不同用户），于是有了四级回退：运行架构的 cputype 与 subtype 都匹配 → 只有 cputype 匹配（Rosetta 进程）→ 宿主架构的 cputype → 第一片。即便如此，1708 个进程里仍有约 4.6% 判不出平台，主要是取不到路径的受保护系统进程。冷解析 1398 个进程约 14.8 ms，平台按路径缓存。

换成内核查询后，读文件、挑切片、按路径缓存都不再需要，解析器与它的 26 个测试（`MachOPlatformTests`、`MachOFixture`）一并删除；代码保留在 0.7.0 及以前的历史里。当时用变异测试得出的教训对任何手写解析器仍然适用：fixture 构造得太宽松，会让别的分支替被测分支兜底，初版有两处变异没被测出来，修法是把 fixture 收窄到只有目标分支能解释结果。

## 验证

- `KernelValueMappingTests`：内核值 0 为 `nil`，1、6、7 分别是 macOS、Mac Catalyst、iOS Simulator，99 保留为 `.unknown(99)`。
- `LocalProcessTests`：测试进程自己与 Finder 的平台都是 `.macOS`。同样两个测试对着旧实现也通过，说明这两类进程的结果没变。swift-proc 自己的测试也确认了当前进程查到 `PLATFORM_MACOS`。
- **未验证**：模拟器 guest 进程、Mac Catalyst 应用、iPad app on Mac 的实际返回值。按 xnu 源码它们会分别得到 7、6、2，但这次没有实测：模拟器需要单独授权才能启动。

## 已知降级

- 内核报 0 或拒绝查询（进程已消失、MAC 策略不允许）时，`platform` 为 `nil`。
- 依赖 SDK 没有声明的内核接口。若未来系统改了它，查询会失败，`platform` 退化为 `nil`，不会崩溃。
- `Platform` 里的 ExclaveCore / ExclaveKit 平台（见[术语表](../Glossary.md#exclavecore--exclavekit)）收录只为忠实于 Mach-O ABI，普通进程列表里不会出现。

## 后续工作

- 有授权启动模拟器时，实测一次 guest 进程的返回值，并把结果补进「验证」。
- 若日后要标宿主侧的 CoreSimulator 支撑进程（`CoreSimulatorService`、`SimRenderServer` 等），那是**另一个判定维度**，不能塞进 `Platform`：它们的平台确实就是 macOS。应另起一个属性。

## 延伸阅读

- 配套提案：[进程平台识别与模拟器标记](../Evolutions/0001-simulator-platform-detection.md)、[接入 swift-proc](../Evolutions/draft-adopt-swift-proc.md)
- 术语：[guest 进程、platform](../Glossary.md)
