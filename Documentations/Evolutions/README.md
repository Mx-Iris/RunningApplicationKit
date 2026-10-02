# Evolution 提案

- **项目类型**: 库（源码分发）

本目录记录 RunningApplicationKit 的每一次实质变更 —— 从前期调研到最终落地都写在同一份文件里，
随实现推进原地更新状态，不另起新文件。被否决的提案保留不删，它是「当初为什么没这么做」的唯一记录。

编号在提案合入 `main` 的那个 commit 里才分配；创建期的提案文件名为 `draft-<slug>.md`，
按 slug 引用。

## 状态总表

| # | 标题 | 状态 | 最后更新 |
|---|------|------|----------|
| 0001 | [进程平台识别与模拟器标记](0001-simulator-platform-detection.md) | Implemented | 2026-08-25 |
| 0002 | [选择器呈现样式（表格与列表）](0002-picker-presentation-styles.md) | Implemented | 2026-08-26 |
| 0003 | [由调用方提供清单的选择器](0003-injected-item-source.md) | Implemented | 2026-10-02 |

## 状态机

`Draft` → `In Review` → `Accepted` → `In Progress` → `Implemented`，
另有 `Rejected` / `Deferred` / `Withdrawn`。

**提案未经批准（状态置为 `Accepted`）不得开始写实现代码。**
