# Curated Development History

**English** · [简体中文](#简体中文) · [Documentation index](../README.md)

This public history preserves reusable product and engineering milestones. It excludes personal machine paths, one-off automation, account details, and obsolete build locations. Complete raw notes remain in the private development archive.

## 0.3.x: local-player foundation

- Established a shared Flutter structure for Windows and Android.
- Used SQLite for library, playlists, favorites, settings, and playback history.
- Added local import, search, playback modes, and the immersive vinyl page.
- Introduced wallpapers, theme colors, and user-selected backgrounds.

## Early 0.4: desktop interaction and MVs

- Unified audio and local MVs in one library and playback flow.
- Added audio/MV pairing, unpairing, video progress, and per-track capability detection.
- Reworked desktop batch management into in-list selection.
- Added collapsible and filterable frequent playlists.
- Unified players, menus, and content cards around theme-aware liquid glass.

## Data and statistics

- Expanded playback events from a simple counter into data supporting recents and time-window charts.
- Moved favorites, playlists, charts, queues, and deletion toward stable IDs and a single state source.
- Added cloud-library search, filtering, sorting, artist grouping, and explicit cloud-copy deletion semantics.

## Reliability phase

Repeated real-world and high-frequency testing focused on:

- stale queues after starting playback from another page;
- black frames, stale UI, or incorrect capability detection during audio/MV changes;
- sound and UI divergence after rapid next-track input;
- concurrent cloud requests, false offline errors, and crashes after repeated clicks;
- stale references after deleting the current track;
- context-menu anchoring, duplicate scrollbars, and window-scaling behavior.

These failures drove request generations, cancellation and deduplication, one authoritative playback state, per-track media capability, and a systematic regression matrix.

## Smart metadata and text covers

- Import reads media tags first and then cleans filenames.
- MusicBrainz supplies structured candidates.
- Windows optionally falls back to Chromaprint / AcoustID fingerprints.
- Text covers preserve a short semantic title instead of a single arbitrary character while remaining readable at small sizes.
- Identification results can be previewed so low-confidence data does not silently overwrite the library.

## Internationalization and public release

- Added Simplified Chinese, Traditional Chinese, and English UI.
- Built a bilingual promotional website with responsive real-product screenshots and GitHub Pages deployment.
- Made the README English-first with a complete Chinese version on the same page.
- Published curated bilingual architecture, design, testing, and maintenance documents.
- Distributed Windows ZIP and Android APK public-preview builds through GitHub Releases.

## Current direction

The public preview prioritizes stability, media-state consistency, complete localization, and recoverable data. Lyrics, deeper identification, cross-device sync, and additional platforms are future enhancements and must not weaken offline playback.

---

## 简体中文

**[English](#curated-development-history)** · 简体中文 · [文档索引](../README.md#简体中文)

这份公开记录保留可复用的产品与工程演进，不包含个人电脑路径、一次性自动化、账号信息或失效构建位置。完整原始日志继续保留在私有开发资料中。

### 0.3.x：本地播放器基础

- 建立 Flutter Windows / Android 双端结构。
- 使用 SQLite 保存曲库、歌单、收藏、设置和播放记录。
- 完成本地文件导入、搜索、播放模式和沉浸式黑胶页面。
- 引入多套壁纸、主题色和用户自定义背景。

### 0.4 初期：桌面交互与 MV

- 音频和本地 MV 进入统一曲库与播放流程。
- 增加歌曲/MV 配对、解除配对、视频进度和逐曲媒体能力识别。
- 桌面批量管理改为列表内选择模式。
- 侧栏常用歌单支持折叠与筛选。
- 播放器、菜单和内容卡片逐步统一为主题化液态玻璃。

### 数据与统计

- 播放事件从简单累计次数扩展为支持最近播放和周期排行的数据。
- 收藏、歌单、排行、队列和删除逐步统一到稳定 ID 与单一状态源。
- 云端资料库增加搜索、筛选、排序、按歌手分组和明确的云副本删除语义。

### 可靠性阶段

多轮真实操作与高频压力测试重点处理：从不同页面播放时沿用旧队列；音频/MV 切换时黑屏、画面不更新或能力判断错误；快速下一首造成声音与界面不同步；重复点击云端歌曲造成并发请求、错误离线提示或崩溃；删除当前歌曲后遗留引用；以及右键菜单位置、重复滚动条和窗口缩放问题。

这些问题推动了请求代次、取消与去重、单一播放状态、逐曲媒体能力判断和系统化回归矩阵。

### 智能元数据与文字封面

- 导入阶段优先读取媒体标签并清理文件名。
- 引入 MusicBrainz 候选查询。
- Windows 端加入可选 Chromaprint / AcoustID 声纹回退。
- 文字封面尽量保留完整的短语义标题，同时维持小尺寸可读性。
- 识别结果支持预览，避免低置信度数据直接覆盖曲库。

### 国际化与公开发布

- 增加简体中文、繁體中文和 English 界面。
- 建立中英文宣传网站、响应式真实截图和 GitHub Pages 发布流程。
- README 采用英文优先、完整中文同页展示。
- 公开文档以完整双语保留架构、设计、测试和维护知识。
- Windows ZIP 与 Android APK 通过 GitHub Releases 提供公开预览下载。

### 当前方向

公开预览阶段优先级是稳定性、媒体状态一致性、完整本地化和数据可恢复性。歌词、进一步的智能识别、跨设备同步和更多平台支持属于后续增强，不应牺牲离线播放主链路。
