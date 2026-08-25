# 术语表

本项目专有名词与约定用法。

跨项目通用的术语（Mach-O、slice、ABI 与源码兼容性之别、entitlement 等）收录在全局术语表中，
本表只收本项目特有的，不重复登记。全局表不在本仓库内，位于 iCloud Global 镜像的
`Documentations/Glossary.md`。

## 维护约定

提案或专题文章引入新术语时，**同批次**登记进本表。文档里首次出现该术语时展开一次并链到这里，
之后不必每篇重复解释。

## 术语

### ExclaveCore / ExclaveKit

Apple 的 Secure Exclave 隔离执行环境，在 Mach-O 平台常量表里占 15–24 号（macOS、iOS、tvOS、
watchOS、visionOS 各有一对）。`Platform` 枚举把它们全部收录以求对 Mach-O ABI 忠实，但
**实测 1708 个进程里一个都没有出现** —— 它们不是普通 BSD 进程，不会进程序列表。

见到它们的唯一现实途径是直接解析某个系统二进制文件。

- **主要出现在**：`Sources/RunningApplicationKit/Platform.swift`

### guest 进程

运行在**模拟器沙盒内部**的进程 —— SpringBoard、被调试的 app，以及模拟器里那整套 iOS 自己的
daemon（`logd`、`runningboardd`、`cfprefsd` …）。

与之相对的是**宿主侧支撑进程**：`CoreSimulatorService`、`SimRenderServer`、`SimMetalHost`、
`Simulator.app` 等，它们跑在 macOS 上、为模拟器服务，本身是货真价实的 macOS 进程。

**本项目只标 guest 进程。** 判据是二进制的 Mach-O 平台是不是模拟器平台，宿主侧支撑进程的平台就是
`macOS`，因此不会被标记 —— 这是有意的，不是漏判。

- **主要出现在**：[平台识别实现说明](Internal/PlatformDetection.md)
- **延伸阅读**：[进程平台识别与模拟器标记](Evolutions/0001-simulator-platform-detection.md)

### platform（本项目含义）

特指 Mach-O `LC_BUILD_VERSION` 载荷命令里的 `PLATFORM_*` 常量，即这个二进制**被编译成给哪个平台跑**。

**不要与 `architecture` 混为一谈**，这一对是本项目最容易搞混的近义词：

| | 回答什么 | 数据来源 | 能区分模拟器吗 |
|---|---|---|---|
| `architecture` | 内核**实际以什么架构运行**这个进程 | `proc_pidinfo` + `PROC_PIDARCHINFO` | **不能** |
| `platform` | 二进制**被编译成给哪个平台** | 可执行文件的 Mach-O 头 | 能 |

Apple Silicon 上模拟器里的进程跑的是原生 arm64，架构与宿主进程完全一致 —— 这正是需要引入
`platform` 的原因。

- **主要出现在**：`Sources/RunningApplicationKit/Platform.swift`、
  `Sources/RunningApplicationKit/MachOPlatform.swift`
- **延伸阅读**：[平台识别实现说明](Internal/PlatformDetection.md)
