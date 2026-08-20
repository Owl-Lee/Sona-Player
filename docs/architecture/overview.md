# Sona Architecture and Data Flow

**English** · [简体中文](#简体中文) · [Documentation index](../README.md)

## 1. Product boundary

Sona is a personal music player for Windows and Android. It manages and plays audio and local MVs owned by the user; it does not provide an online copyrighted catalog. Its priorities are:

1. reliable local playback;
2. consistent library data;
3. explicit, recoverable interactions;
4. cloud services and online identification as optional enhancements.

When the network is unavailable, the local library, queue, playlists, favorites, history, and cached media must continue to work. A cloud failure may interrupt a cloud action, but must never bring down the playback path.

## 2. Technical structure

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

SQLite stores tracks, file locations, media types, playlist relationships, favorites, playback events, and settings. Media bytes stay in user files or application caches; structured records and large media objects are not mixed in the same database table.

## 3. Import and deduplication

```text
Select files or scan a folder
  → detect audio / video type
  → read tags, duration, and embedded artwork
  → clean the filename and infer title / artist candidates
  → derive a stable file identity
  → deduplicate and write to SQLite
  → refresh the current view and playback entry points
```

Paths and filenames can change, so neither should be the sole identity of a track. A content hash can identify an identical file. Different encodings, live versions, and paired MVs remain separate media resources connected through metadata or an explicit pairing.

## 4. Playback and queues

Every entry point—local library, recents, favorites, playlists, charts, and cloud lists—submits the same set of information to one playback coordinator:

- the selected track;
- a queue generated from the currently visible list;
- a human-readable queue source;
- per-track capabilities such as audio, MV, and artwork;
- the selected playback mode.

Selecting a track in another list must replace the previous queue. Previous/next changes the authoritative current track first, then chooses the MV or vinyl view from that track's actual capabilities. The UI must never infer the whole queue's media type from its first item.

## 5. Metadata identification

Identification uses layered fallback:

1. **Embedded tags:** fastest and fully offline, but possibly missing or incorrect.
2. **Filename semantics:** removes numbering, source markers, episode suffixes, and download identifiers, then infers title and artist.
3. **MusicBrainz:** supplies structured candidates for canonical names and albums.
4. **Chromaprint / AcoustID:** generates a fingerprint locally and submits only the fingerprint and duration as a fallback for difficult tracks.

Online data is a candidate, not absolute truth. Low-confidence changes should be previewed and confirmed. Batch cleanup must not silently overwrite metadata already confirmed by the user.

## 6. Cloud boundary

Cloud sync is an enhancement layer:

- complete local writes before attempting sync;
- make requests cancellable, deduplicated, bounded by timeouts, and retryable;
- repeated clicks on one cloud item must not create unlimited downloads or playback tasks;
- stale responses must not overwrite a newer selection;
- deleting a cloud copy must not delete the local file unless the user explicitly chooses local deletion.

Account data, favorites, playlists, and playback events are structured records; audio and MVs are large objects. Production deployments must use least privilege and must never ship administrator keys or database passwords in the client.

## 7. State consistency

- The player has one authoritative current track and one authoritative queue.
- Pages render shared state instead of owning a second long-lived playback state.
- Track deletion also removes playlist, favorite, chart-cache, and queue references.
- Before committing an asynchronous result, compare its request generation with the current selection and discard stale work.
- User-facing errors explain the next useful action without exposing database exceptions or service configuration.

---

## 简体中文

**[English](#sona-architecture-and-data-flow)** · 简体中文 · [文档索引](../README.md#简体中文)

### 1. 产品边界

Sona 是 Windows 与 Android 上的私人音乐播放器。它管理并播放用户自己拥有的音频和本地 MV，不提供在线版权曲库。设计优先级依次是：

1. 本地播放可靠；
2. 曲库数据一致；
3. 交互明确且可恢复；
4. 云端与在线识别作为可选增强。

网络断开时，本地曲库、播放队列、歌单、收藏、播放记录和已缓存媒体仍应工作。云端失败只能影响云端操作，不能拖垮播放器主链路。

### 2. 技术结构

整体结构与上方架构图一致：Flutter UI 通过 Riverpod 管理应用状态，由单一播放协调层处理音频、MV、队列、模式和进度；SQLite 保存结构化曲库数据，媒体文件保留在用户文件或缓存中；识别与云同步均为可回退的增强层。

### 3. 导入与去重

导入流程依次判断媒体类型，读取标签、时长和封面，清理文件名，生成稳定文件身份，在 SQLite 中去重写入，最后刷新当前列表和播放入口。路径和文件名可能改变，因此不能单独作为歌曲身份。内容哈希适合识别完全相同的文件；不同编码、现场版和配对 MV 则作为独立媒体资源，通过资料或显式配对建立关系。

### 4. 播放与队列

本地曲库、最近播放、收藏、歌单、排行和云端列表都向同一个播放协调层提交当前曲目、当前可见列表生成的队列、队列来源、逐曲媒体能力和播放模式。点击另一个列表中的歌曲时必须替换旧队列。上一首和下一首先更新权威当前曲目，再按该曲目的实际能力决定显示 MV 或唱片页，不能用队列第一首推断整列类型。

### 5. 歌曲信息识别

识别按层回退：优先读取本地媒体标签，再解析文件名语义；必要时查询 MusicBrainz；困难样本可在本地生成 Chromaprint 声纹，并把声纹与时长交给 AcoustID 查询。在线结果只是候选而非绝对真相，低置信度修改应预览确认，批量整理不得静默覆盖用户已经确认的资料。

### 6. 云同步边界

云同步是增强层。本地写入先完成，再尝试同步；请求必须可取消、去重、超时和重试；重复点击不得无限创建任务；过期响应不得覆盖新选择；删除云副本不能连带删除本地文件，除非用户明确选择本地删除。实际部署遵循最小权限，管理员密钥和数据库密码绝不能进入客户端。

### 7. 状态一致性原则

- 播放器只有一个权威当前曲目和一个权威队列。
- 页面只呈现共享状态，不复制长期独立的播放状态。
- 删除曲目时同步清理歌单、收藏、排行缓存和队列引用。
- 异步结果写入前检查请求代次并丢弃过期结果。
- 错误提示说明用户能采取的下一步，不暴露数据库异常或服务配置。
