# Draft - 接入 swift-proc

- **状态**: In Progress
- **创建日期**: 2026-10-17
- **最后更新**: 2026-10-17
- **实现分支**: `feature/adopt-swift-proc`
- **配套文档**: [平台识别实现说明](../Internal/PlatformDetection.md)（随本提案改写）；术语见[术语表的内核名](../Glossary.md#内核名kernel-name)

## 摘要

把 `BSDProcess` 里手写的 libproc 调用换成 [swift-proc](https://github.com/Mx-Iris/swift-proc)（libproc 的 Swift 封装，同一作者）。顺带做三件事：

- **修好进程名**：`BSDProcess.name(for:)` 给 `proc_name` 的缓冲区只有 17 字节，而它要求至少 32 字节，所以进程名**从来没有取到过**。表面上看不出来，是因为名字一直回退到可执行文件名；但按名字观察进程（`RunningProcessObserver(target: .name(…))`）因此永远匹配不到，取不到路径的进程也因此整个从列表里消失。
- **平台识别改为问内核**，不再读可执行文件的 Mach-O 头。[0001](0001-simulator-platform-detection.md) 的前提「内核问不到进程平台」不成立，理由见下文。
- **按进程号观察在 macOS 15 起改为事件驱动**：进程一退出就回调，不再等最多一个轮询间隔。

部署目标从 macOS 11 升到 12，是破坏性变更，下个版本应为 0.8.0。

## 方案

### 依赖与部署目标

- 依赖 `.package(url: "https://github.com/Mx-Iris/swift-proc.git", from: "0.1.0")`，用其中的 `ProcessInformation` 与 `ProcessInformationPrivate` 两个产品。
- 部署目标 `.macOS(.v12)`。swift-proc 最低支持 macOS 12；SwiftPM 不允许低版本的包依赖高版本的包。没有更低的选择：Xcode 27 的 macOS SDK 最低只能部署到 12，本库原先写的 11 在 Xcode 27 下其实已经按 12 构建。已知的四个依赖方都不受影响：RuntimeViewer 与 MachInjector 的示例 app 是 macOS 15，LookInside 与 HopperMCP 是 macOS 14。
- `RunningItemSource` 的存储仍用 `AnyRunningItemSource`：参数化的存在类型要 macOS 13 运行时，12 仍然低于它。

### 替换的调用

| 现在 | 改为 |
|---|---|
| `proc_listpids` | `ProcessIdentifier.list()` |
| `proc_name`，17 字节缓冲区 | `ProcessIdentifier.name()` |
| `proc_pidpath` | `ProcessIdentifier.executablePath()` |
| `proc_pidinfo` 加手写的 `PROC_PIDARCHINFO = 19` | `ProcessIdentifier.architecture()` |
| 读可执行文件的 Mach-O 头（`MachOPlatform`） | `ProcessIdentifier.platform()`，即私有 flavor `PROC_PIDPLATFORMINFO` |

`kill(pid, 0)` 判断进程是否存在、Security 框架判断沙盒，都不属于 libproc，保持不变。

### 平台识别改为问内核

0001 的结论来自一次扫描：用 8 字节缓冲区逐个试 `proc_pidinfo` 的 flavor 1–64，只有 1、6、19、28、32、34 有返回。但 xnu 从 macOS 10.15（xnu-6153）起就有 `PROC_PIDPLATFORMINFO`（flavor 30）：

- 它返回 4 字节的 `uint32_t`，8 字节缓冲区能通过 `proc_pidinfo_internal` 的大小检查（`buffersize < size` 才报错）。扫描漏掉它，推测是只把返回 8 字节的算作「有返回」。
- `proc_info.c` 把它列在免同用户检查的 flavor 里，也会去找 zombie，所以任何调用方都能查任何用户的进程。`PROC_PIDARCHINFO` 没有这项豁免，0001 的四级切片回退正是为它对 279 个进程不可用而加的。
- 内核在 exec 时从**实际加载的那个切片**读 `LC_BUILD_VERSION`（没有时读旧式的 `LC_VERSION_MIN_*`）记下平台（mach_loader.c；kern_exec.c 的 `proc_setplatformdata`），fork 出的进程继承父进程的值。这正是 0001 想回答的「这个二进制被编译给哪个平台」，而且不用读文件，也不用猜胖二进制该读哪个切片。

因此删除 `MachOPlatform.swift` 与它的测试（`MachOPlatformTests`、`MachOFixture`）。`Platform` 枚举、它的显示与排序不变；内核值 0 表示没有记录平台，映射为 `nil`。swift-proc 的测试已确认当前进程查到的是 `PLATFORM_MACOS`；模拟器进程上的实测需要启动模拟器，本次不做。

### 架构与平台不再按路径缓存

两者都改为每次按进程查内核，去掉 `RunningProcessEnumerator` 里按可执行文件路径的架构缓存与 `MachOPlatform` 的平台缓存。缓存原本是为了省掉读文件（冷解析约 0.02 ms 一个文件），内核查询本身只是一次系统调用。按路径缓存还有一个错误：同一个通用二进制可能一个实例在 Rosetta 下以 x86_64 运行、另一个原生运行，按路径缓存会把第一个查到的架构套给所有实例。

代价：内核只对同一用户的进程回答架构。以前别的用户的进程若与本用户的某个进程共用一个可执行文件，会沿用缓存里那个实例的架构；现在这些进程的 `architecture` 是 `nil`。平台没有这个限制，所以反而比以前覆盖得更全。

### 进程名

优先用可执行文件名，取不到路径时才用内核记录的名字（`p_name`，对外最多 31 字节）。理由：bug 期间显示的一直是文件名，按这个顺序，列表里现有的名字一个都不变；而内核名会把超过 31 字节的名字截断。变化只有一处：取不到路径、但能取到内核名的进程，之前被整个丢掉，现在带着内核名出现。内核名只对同一用户的进程可查，所以这类进程不多。

### 观察器

- **`.name`**：内核名或可执行文件名任一与目标相等即算匹配，所以按列表里看到的名字观察也能匹配上。
- **`.pid`**：macOS 15 起，进程在运行时用 swift-proc 的 `waitForTermination()`（kqueue 的 `NOTE_EXIT`）等它退出，退出时立即回调 `onTerminate`；之后回到轮询，等同一个进程号再次出现（保留原来的 `onLaunch` 语义）。注册失败（取消以外的错误）时退回轮询。macOS 12–14 仍是轮询，因为 `waitForTermination()` 要 macOS 15。
- **`.executablePath`**：不变。

### 测试

本库的测试第一次读真实进程（以前全部是纯函数与界面结构测试）：

- 测试进程自己：`RunningProcessEnumerator.makeProcess(for:)` 给出的名字与平台。
- 运行中的应用：Finder 的 `RunningApplication.platform`。
- 按名字观察：复制 `/bin/sleep` 成一个名字唯一、长于 31 字节的可执行文件并启动，按截断后的内核名与按完整文件名的两个 `.name` 目标都应报告启动与退出。修复前失败。
- 按进程号观察：轮询间隔设为 30 秒，杀掉子进程后应在 2 秒内报告退出。修复前失败。
- 架构映射与内核平台值映射各一组纯函数测试。

### 不做

- 不改任何公开类型的形状。
- 不打 tag、不发版，版本号由用户决定。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-10-17 | Created as Draft：「RunningApplicationKit接入一下这个库」 | — |
| 2026-10-17 | 部署目标 macOS 11 → 12 | 用户决定（「那就改成最低12.0，RAK也改」）。备选「升到 15」会让 LookInside、HopperMCP 下次更新依赖时编译失败；「swift-proc 降到 11」在 Xcode 27 下做不到 |
| 2026-10-17 | 按 URL 依赖 swift-proc 0.1.0，swift-proc 公开发布 | 用户选择「提交并公开发布」。本库是公开仓库，本地路径依赖会让所有依赖方解析失败，私有仓库别人拉不到 |
| 2026-10-17 | 平台识别改为问内核；按进程号观察改为事件驱动 | 用户在澄清提问中选择这两项 |
| 2026-10-17 | 状态改为 Accepted | 需要拍板的三项已由用户在上面三行里定下；其余是开工前列给用户的假设：进程名优先用文件名、`.name` 匹配两种名字、去掉按路径的缓存、测试读真实进程 |
| 2026-10-17 | 状态改为 In Progress | 开始实现；开发期间先按本地路径依赖 swift-proc，发布后切成 URL |
| 2026-10-17 | 新测试先对旧实现跑一遍 | 在停在 `main` 的临时 worktree 里跑：按名字观察（两个观察器都收不到启动与退出）、按进程号即时报告退出，两项失败；测试进程与 Finder 的名字和平台两项通过，说明这部分行为没变 |
| 2026-10-17 | 按名字观察的测试改用复制的可执行文件，不用符号链接 | 实测：通过符号链接启动时，内核名是链接解析到的文件名（`sleep`），不是链接名。最初以 `ps -c` 的输出为据误判，它显示的是 `argv[0]` |
| 2026-10-17 | 内核名的上限写成 31 字节 | 实测加 proc_info.c：`p_name` 存 32 字节，但 `proc_pidbsdinfo` 在第 31 字节处写结束符。swift-proc 的文档同批改正 |
| 2026-10-17 | 应用平台的测试改用 Finder | 测试运行器在 Launch Services 里不是应用，它的 `NSRunningApplication.current` 进程号是 -1。顺带确认了一项改进：旧实现对没有 `executableURL` 的应用报不出平台，新实现按进程号问内核，不需要它 |
| 2026-10-17 | 测试：63 个全部通过（Xcode 27，连续两次），Example app 构建通过 | 原 83 个，删掉 26 个 Mach-O 解析测试，新增 `LocalProcessTests`（4 个）与 `KernelValueMappingTests`（2 个，其一为 8 组参数） |
| 2026-10-17 | 依赖切成 `https://github.com/Mx-Iris/swift-proc.git` 的 `from: "0.1.0"` | swift-proc 0.1.0 已公开发布。切换后从 GitHub 解析到 0.1.0（提交 7d7b4ca），63 个测试通过；Xcode 26.6 构建（含测试）通过；Example app 构建通过 |
| 2026-10-17 | 提交 `Package.resolved` | 本库第一次有依赖，没有先例。同作者其他有依赖的库多数提交它（CocoaCoordinator、RxAppKit、SourceEditor、UXKitCoordinator、idax、swift-helper-service），只有 CatalystAppKit 忽略。库的 `Package.resolved` 不影响依赖方，只固定本仓库自己开发与测试时解析到的版本 |
