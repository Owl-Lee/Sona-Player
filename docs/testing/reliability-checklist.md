# Reliability Test Matrix

**English** · [简体中文](#简体中文) · [Documentation index](../README.md)

> The goal is not to prove that one normal click works. The goal is to expose races, repeated-input failures, boundary data, and resource-lifecycle defects.

## 1. Baseline

- Run core flows on Windows and Android.
- Cover cold start, warm switching, and failure recovery.
- Test light, dark, warm, cool, and custom wallpapers.
- Record entry point, queue source, media type, network state, and final UI—not merely “it froze.”

## 2. Playback and queues

- Start tracks from library, recents, favorites, playlists, charts, and cloud lists; verify that the queue source changes immediately.
- Press previous/next rapidly 20 times; sound, title, cover, duration, MV/vinyl view, and queue highlight must converge on one item.
- Switch audio → MV → audio and MV → MV; check for black frames, position resets, stale capability labels, and leftover sound.
- Exercise repeat-all, repeat-one, sequential, and shuffle at both queue boundaries.
- Navigate, minimize, restore, and open/close the queue during playback without restarting or losing state.

## 3. Import, pairing, and deletion

Cover these combinations:

- audio only;
- MP4/MV only;
- audio first, then pair an MV;
- MV first, then associate audio;
- delete the MV while retaining audio;
- delete audio while retaining an independent MV;
- delete the currently playing item;
- delete the first, middle, and last queue items;
- re-import the same file, a same-name different file, and the same file after rename.

After deletion, inspect library, favorites, recents, charts, playlists, cloud copy, and current queue for stale references. Destructive actions must distinguish “remove from library,” “delete cloud copy,” and “delete local file.”

## 4. Cloud and network

- Test online, offline, interrupted request, and restored-network states.
- Click a cloud track repeatedly and rapidly; stale requests must be cancelled or ignored without unlimited downloads, false offline errors, or crashes.
- Advance past the last cloud item; obey the active queue mode instead of entering an empty gray state.
- Repeat refresh, search, filter, sort, and cloud deletion while checking scroll position and context-menu anchoring.
- A cloud failure must not freeze the local library or stop a playing local track.

## 5. Metadata identification

- Test complete tags, missing tags, noisy filenames, Simplified Chinese, Traditional Chinese, English, live recordings, and compilation chapters.
- During rapid repeated identification, replace the current notification instead of building a long message queue.
- AcoustID unavailable, rate limited, unmatched, and low-confidence states must use clear, non-technical messages.
- After switching interface language, verify menus, notifications, empty states, and language-preferred metadata aliases.
- Preview batch differences; low-confidence results must not overwrite user-confirmed data.

## 6. UI and input

- Resize to compact, ordinary, maximized, and multiple system scaling levels.
- Ensure the sidebar has one scrollbar and no list scrollbar overlaps a glass border.
- Open context menus near all four window edges and verify automatic flipping.
- Move from the volume button onto its hover slider without accidental dismissal; clicking the button only toggles mute.
- On Android, keep fields and submit actions reachable after the soft keyboard opens.

## 7. Exit criteria

One passing run is not enough. A high-risk fix needs automated checks, real Windows UI regression, the related Android regression, and a sustained stress pass. For media-dependent bugs, retain a minimal legal sample or record its format, duration, and tag characteristics.

---

## 简体中文

**[English](#reliability-test-matrix)** · 简体中文 · [文档索引](../README.md#简体中文)

> 目标不是证明“正常点一次能工作”，而是主动寻找状态竞争、重复操作、边界数据和资源释放问题。

### 1. 基础原则

- Windows 和 Android 都执行核心流程。
- 每项覆盖冷启动、热切换和失败恢复。
- 测试浅色、深色、暖色、冷色和自定义壁纸。
- 记录操作入口、队列来源、媒体类型、网络状态和最终界面，不只记录“卡了”。

### 2. 播放与队列

- 从曲库、最近播放、收藏、歌单、排行和云端列表分别点击，确认队列来源立即切换。
- 快速连续点击 20 次上一首/下一首，最终声音、标题、封面、时长、MV/唱片视图和队列高亮必须一致。
- 在音频 → MV → 音频、MV → MV 间切换，检查黑屏、位置归零、错误能力标签和声音残留。
- 在队列首尾验证列表循环、单曲循环、顺序和随机模式。
- 播放中切页面、最小化、恢复、打开或关闭队列，不得重播或丢失状态。

### 3. 导入、配对与删除

组合覆盖：只有音频；只有 MP4/MV；先音频后配对 MV；先 MV 后关联音频；删除 MV 保留音频；删除音频保留独立 MV；删除当前播放项；删除队列首项、中间项和末项；重复导入相同文件、同名不同文件和改名后的同一文件。

删除后检查曲库、收藏、最近播放、排行、歌单、云端副本和当前队列，不能留下无效引用。危险操作明确区分“移出曲库”“删除云副本”和“删除本地文件”。

### 4. 云端与网络

- 分别测试在线、离线、请求中断和网络恢复。
- 快速重复点击云端歌曲，确保旧请求取消或被忽略，不出现无限下载、错误离线提示或闪退。
- 云端列表最后一首继续下一首时按队列模式处理，不能进入空白全灰状态。
- 重复刷新、搜索、筛选、排序和删除云副本，检查滚动位置与菜单锚点。
- 云端失败不得冻结本地曲库或停止正在播放的本地歌曲。

### 5. 元数据识别

- 测试标签完整、标签缺失、文件名混乱、简体、繁体、英文、现场版和合集分集。
- 快速连续识别时，新提示替换旧提示，不排成长时间消息队列。
- AcoustID 未配置、限流、无匹配和低置信度都使用清楚但不过度技术化的提示。
- 切换界面语言后检查菜单、提示、空状态和按语言偏好选择的资料别名。
- 批量应用前预览差异，低置信度结果不得覆盖用户确认的数据。

### 6. 界面与输入

- 调整窗口到窄屏、常规、最大化和多种系统缩放比例。
- 侧栏只出现一根滚动条，列表滚动条不与玻璃边缘重叠。
- 在窗口四边测试右键菜单自动翻转。
- 鼠标能从音量按钮移入滑条而不意外关闭，单击按钮只切换静音。
- Android 软键盘弹出后，输入框和提交按钮仍可见可点。

### 7. 完成标准

一次通过不等于关闭问题。高风险修复至少需要自动化检查、Windows 真实窗口回归、相关 Android 回归和一轮持续压力测试。若问题依赖媒体文件，应保留合法的最小复现样本，或记录格式、时长和标签特征。
