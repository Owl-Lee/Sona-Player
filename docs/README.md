# Sona Documentation / 项目文档

These documents preserve the engineering decisions behind Sona. Public copies are curated from the project's long-form design notes: machine-specific paths, credentials, temporary workarounds and obsolete instructions are intentionally excluded.

这里保留 Sona 的架构、交互、测试和维护思路。公开版本整理自项目长期文档，已去除个人电脑路径、密钥、临时操作步骤和过时结论；开发者自己的完整原始记录仍保留在私有开发仓库中。

| Document | 内容 |
| --- | --- |
| [Architecture and data flow](architecture/overview.md) | 本地优先架构、数据模型、播放与识别链路、云同步边界 |
| [Interaction and motion guidelines](design/interaction-and-motion.md) | 液态玻璃、键鼠交互、响应式布局、键盘避让与动画原则 |
| [Reliability test matrix](testing/reliability-checklist.md) | 播放、队列、MV、导入删除、离线和高频操作的回归矩阵 |
| [Development and maintenance guide](contributing/development-guide.md) | 构建、验证、提交范围与安全边界 |
| [Curated development history](history/development-notes.md) | 从本地播放器到公开预览版的重要演进 |

## Documentation policy / 文档维护规则

1. Current code and the root [`README.md`](../README.md) take priority over historical notes.
2. Implemented, planned and experimental features must be labeled separately.
3. Never publish API keys, passwords, private database credentials, user file paths or personal account details.
4. Replace machine-specific absolute paths with repository-relative paths.
5. Keep raw debugging logs private; publish the reusable conclusion and verification method.

[Back to project README](../README.md)
