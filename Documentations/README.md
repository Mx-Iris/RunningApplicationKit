# 文档索引

RunningApplicationKit 的内部文档。逐条列出本目录下所有文档及其一句话说明 ——
新增或重命名任何文档都必须同步更新这份索引。

正文用中文，标识符与技术术语保持英文。面向公众的文档（`README.md`、`LICENSE`）用英文，
不在本目录内。

## Evolutions —— 提案

每一次实质变更一篇，记录为什么要做、打算怎么做、放弃了什么。状态总表见
[Evolutions/README.md](Evolutions/README.md)。

| 文档 | 说明 |
|------|------|
| [0001-simulator-platform-detection.md](Evolutions/0001-simulator-platform-detection.md) | 读 Mach-O `LC_BUILD_VERSION` 判定进程平台，在 Processes 标签页标出模拟器进程 |
| [0002-picker-presentation-styles.md](Evolutions/0002-picker-presentation-styles.md) | 给两个标签页各加一个 `style`，表格之外新增列表样式；`allowsColumns` 改名为 `allowsFields` 并保留弃用别名 |
| [draft-injected-item-source.md](Evolutions/draft-injected-item-source.md) | 让调用方把自己手上的进程清单交给选择器显示（为「挑另一台机器上的进程」而加）；选不中的行变灰；`kernel_task` / `launchd` 默认不可选中 |

## Internal —— 实现说明

面向维护者：最终怎么实现的、为什么这么实现、有什么降级。

| 文档 | 说明 |
|------|------|
| [PlatformDetection.md](Internal/PlatformDetection.md) | 平台识别的落地细节：内核为什么问不到、slice 四级回退的实测依据、变异测试结论与已知降级 |
| [PresentationStyles.md](Internal/PresentationStyles.md) | 表格与列表两种呈现的落地细节：为什么列表仍是 NSTableView、样式默认值怎么不破坏公开类型、旧 init 消歧义的约束、骨架屏与提案的差异 |

## 术语表

| 文档 | 说明 |
|------|------|
| [Glossary.md](Glossary.md) | 项目术语：field 与 column 之别、style、guest 进程、platform 与 architecture 之别、ExclaveCore / ExclaveKit |

## 历史文档

`docs/plans/` 下曾有两份 2026-03-08 的旧格式文档（进程支持的 design 与 implementation），
早于本目录建立。它们随本目录启用一并删除 —— 同一件事拆成 design 与 implementation 两篇，
没有任何一份是权威的，正是提案制要避免的形态。
