# Sona Documentation

**English** · [简体中文](#简体中文) · [Project README](../README.md)

These public documents preserve Sona's reusable product and engineering decisions. They are curated from the project's long-form notes; machine-specific paths, credentials, private operational details, temporary workarounds, and obsolete instructions are intentionally excluded.

| Document | What it covers |
| --- | --- |
| [Architecture and data flow](architecture/overview.md) | Local-first architecture, data model, playback, identification, and cloud boundaries |
| [Interaction and motion guidelines](design/interaction-and-motion.md) | Liquid glass, desktop input, responsive layout, keyboard avoidance, and motion |
| [Reliability test matrix](testing/reliability-checklist.md) | Playback, queues, MVs, import/deletion, offline behavior, and stress testing |
| [Android player acceptance plan](testing/MOBILE_PLAYER_TEST_PLAN.md) | Automated lifecycle gate and the physical-device evidence required for a release |
| [Windows performance profile](testing/PERFORMANCE_PROFILE_2026-08-22.md) | Profile-mode memory, theme switching, and native-compositor findings |
| [Development and maintenance guide](contributing/development-guide.md) | Build steps, verification, contribution scope, and security boundaries |
| [Release engineering](releases/RELEASE_ENGINEERING.md) | Signing, CI secrets, immutable release assets, checksums, and publication gates |
| [Curated development history](history/development-notes.md) | Major milestones from a local player to the public preview |
| [0.5.0 public preview notes](releases/0.5.0.md) | Data safety, metadata control, performance modes, and reliability updates |
| [0.4.51 public preview notes](releases/0.4.51-preview.1.md) | Permanent Android signing, reliability updates, packages, and checksums |
| [0.4.50 public preview notes](releases/0.4.50-preview.1.md) | Packages, installation notes, and SHA-256 checksums |

## Documentation policy

1. Current code and the root [`README.md`](../README.md) take priority over historical notes.
2. Implemented, planned, and experimental features must be labeled separately.
3. Never publish API keys, passwords, private database credentials, user file paths, or personal account details.
4. Replace machine-specific absolute paths with repository-relative paths.
5. Keep raw debugging logs private; publish the reusable conclusion and its verification method.
6. Public documentation is written in full English first, followed by a complete Simplified Chinese version.

---

## 简体中文

**[English](#sona-documentation)** · 简体中文 · [项目主页](../README.md)

这些公开文档保留 Sona 中可复用的产品与工程决策。内容整理自项目长期记录，已主动移除个人电脑路径、密钥、私有运维信息、临时解决步骤和过时说明。

| 文档 | 内容 |
| --- | --- |
| [架构与数据流](architecture/overview.md#简体中文) | 本地优先架构、数据模型、播放、识别与云端边界 |
| [交互与动效规范](design/interaction-and-motion.md#简体中文) | 液态玻璃、桌面输入、响应式布局、键盘避让与动画 |
| [稳定性测试矩阵](testing/reliability-checklist.md#简体中文) | 播放、队列、MV、导入删除、离线与压力测试 |
| [Android 播放器验收计划](testing/MOBILE_PLAYER_TEST_PLAN.md#中文说明) | 自动生命周期门禁，以及正式发布所需的真机证据 |
| [Windows 性能分析](testing/PERFORMANCE_PROFILE_2026-08-22.md#中文) | Profile 模式内存、换肤和原生合成层结论 |
| [开发与维护指南](contributing/development-guide.md#简体中文) | 构建、验证、贡献范围与安全边界 |
| [发布工程](releases/RELEASE_ENGINEERING.md#中文) | 签名、CI 密钥、固定发布资产、校验值与发布门禁 |
| [开发历程摘要](history/development-notes.md#简体中文) | 从本地播放器到公开预览版的重要演进 |
| [0.5.0 公开预览版说明](releases/0.5.0.md#简体中文) | 数据安全、资料可控性、性能档位与稳定性更新 |
| [0.4.51 公开预览版说明](releases/0.4.51-preview.1.md#简体中文) | Android 永久签名、稳定性更新、安装包与校验值 |
| [0.4.50 公开预览版说明](releases/0.4.50-preview.1.md#简体中文) | 安装包、安装说明与 SHA-256 校验值 |

### 文档维护规则

1. 当前代码和根目录 [`README.md`](../README.md) 的优先级高于历史记录。
2. 已实现、计划中和实验性功能必须分别标注。
3. 不得公开 API Key、密码、私有数据库凭据、用户文件路径或个人账号信息。
4. 用仓库相对路径替代特定电脑上的绝对路径。
5. 原始调试日志保留在私有开发资料中；公开可复用结论与验证方法。
6. 公开文档先提供完整英文，再提供完整简体中文。
