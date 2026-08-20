# Sona Architecture and Data Flow

> 中文为主，附英文摘要。This document describes Sona's current local-first architecture and the boundaries of optional cloud features.

## 1. 产品边界

Sona 是 Windows 与 Android 上的私人音乐播放器。它管理并播放用户自己拥有的音频和本地 MV，不提供在线版权曲库。设计优先级依次是：

1. 本地播放可靠；
2. 曲库数据一致；
3. 交互明确且可恢复；
4. 云端与在线识别作为可选增强。

网络断开时，本地曲库、播放队列、歌单、收藏、播放记录和已缓存媒体仍应工作。云端失败只能影响云端操作，不能拖垮播放器主链路。

## 2. 技术结构

```text
Flutter UI
  ├─ Riverpod application state
  ├─ Playback coordinator
  │    ├─ audio source
  │    ├─ MV source
  │    └─ queue / mode / position
  ├─ Local library repository
  │    ├─ SQLite metadata
  │    └─ user-owned media files
  ├─ Metadata identification
  │    ├─ embedded tags
  │    ├─ filename parser
  │    ├─ MusicBrainz
  │    └─ optional Chromaprint / AcoustID
  └─ Optional cloud sync
       ├─ account and profile
       ├─ metadata and playback events
       └─ explicitly selected cloud media
```

SQLite 保存歌曲、文件位置、媒体类型、歌单关系、收藏、播放事件和设置。媒体字节保留在用户文件或应用缓存中；结构化数据与大文件不混在同一数据库表里。

## 3. 导入与去重

```text
选择文件或扫描文件夹
  → 判断音频 / 视频类型
  → 读取标签、时长和内嵌封面
  → 清理文件名并生成候选标题/歌手
  → 计算稳定文件身份
  → 在 SQLite 中去重并写入
  → 刷新当前筛选结果与播放入口
```

路径和文件名会改变，因此不能单独作为歌曲身份。内容哈希适合判断完全相同的文件；同一首歌的 MP3、FLAC、现场版和 MV 则应作为不同媒体资源，通过曲目信息或显式配对建立关系。

## 4. 播放与队列

所有入口——本地曲库、最近播放、收藏、歌单、排行、云端列表——都应向同一个播放协调层提交：

- 当前曲目；
- 当前入口生成的队列；
- 队列来源名称；
- 媒体能力（音频、MV、唱片封面）；
- 用户选择的播放模式。

点击新的列表项时，队列必须切换为该列表当时的可见结果，不能继续沿用上一个页面的队列。下一首与上一首先更新当前曲目，再根据新曲目的实际媒体能力决定显示 MV 还是唱片页。界面不能仅根据队列第一首推断后续所有项目的类型。

## 5. 歌曲信息识别

识别采用逐层回退：

1. **媒体标签：** 最快，完全离线，但可能缺失或错误。
2. **文件名语义：** 清理编号、来源标记、分集编号和下载尾缀，推断歌曲与歌手。
3. **MusicBrainz：** 用结构化候选补齐规范名称和专辑信息。
4. **Chromaprint / AcoustID：** 在本地生成声纹，只上传声纹和时长查询，作为困难样本回退。

在线返回的是候选数据，不是绝对真相。低置信度结果应允许预览和确认，批量智能整理不得静默覆盖已经由用户确认的资料。

## 6. 云同步边界

云同步是增强层：

- 本地写入先完成，再尝试同步；
- 网络请求必须可取消、去重、超时并允许重试；
- 连续点击同一云文件不得并发创建无限下载或播放任务；
- 旧请求完成时不得覆盖更新的用户选择；
- 删除云副本不能删除本地原文件，除非用户明确选择本地删除。

账号、收藏、歌单和播放事件属于结构化数据；音频与 MV 属于大对象。实际部署必须使用最小权限，并且绝不能把管理员密钥或数据库密码写进客户端。

## 7. 状态一致性原则

- 播放器只有一个权威当前曲目和一个权威队列。
- 页面只呈现状态，不复制一份长期独立的播放状态。
- 删除曲目后同步清理歌单引用、收藏、排行缓存和队列引用。
- 请求结果提交前检查请求代次与当前选择，丢弃过期结果。
- 失败提示描述用户能采取的下一步，不直接暴露数据库异常或服务配置。

[Back to documentation index](../README.md)
