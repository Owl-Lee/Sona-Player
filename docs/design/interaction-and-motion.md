# Interaction and Motion Guidelines

**English** · [简体中文](#简体中文) · [Documentation index](../README.md)

## 1. Visual goals

Sona's liquid glass is more than transparency. Every surface combines a theme-derived tint, visible boundary, stable contrast, and restrained depth. Light themes should not turn cards into harsh white blocks; dark themes should not bury content under heavy shadows.

- Derive glass fills from the active theme and use fine borders with limited shadow.
- Make selected states clearly distinguishable instead of relying on a fill nearly identical to the theme.
- Preserve hierarchy between title, artist, play count, and media-type labels.
- For custom wallpapers, derive foreground contrast from the actual image rather than a preset theme name alone.

## 2. Desktop input

- Left-click a track to play it and build a new queue from the visible list.
- Open the context menu near the pointer and automatically flip it away from window edges.
- Keep frequent menus compact; separate destructive actions and state their scope precisely.
- Reveal the queue as a soft side panel without changing playback or cutting off the main content.
- Clicking volume toggles mute; hovering reveals a vertical slider that remains open while the pointer moves onto it.

## 3. Playback controls

Arrange controls symmetrically around play/pause. Previous and next stay next to the primary control. Loop, queue, favorite, and volume use one consistent relative order across pages. A track change updates title, cover, MV/vinyl capability, duration, and queue highlight together.

## 4. Responsive layout

- Support compact windows, ordinary desktop sizes, and maximized windows instead of designing for one screenshot.
- Use available width, height, and breakpoints to determine columns, spacing, and card width.
- Scale images proportionally; never use a fixed width that cuts the composition in half.
- Titles may truncate gracefully, but key metrics and primary actions remain visible.
- Keep exactly one sidebar scroll container: fixed header and account entry, independently scrollable navigation.

## 5. Keyboard avoidance

When the mobile keyboard appears over login, registration, or editing forms, dialogs should move smoothly, content should remain scrollable, and the primary action should stay reachable.

| Item | Guideline |
| --- | --- |
| Keyboard height | `MediaQuery.viewInsetsOf(context).bottom` |
| Material dialogs | Prefer `AlertDialog` built-in avoidance; do not add a second offset |
| Custom dialogs | 240 ms with `Curves.easeOutCubic` |
| Content resizing | `AnimatedSize`, 180–220 ms |
| Safe area | `SafeArea`, 20–24 dp horizontal and about 24 dp vertical |
| Long content | Scroll the form while keeping actions visible |

Move the container without scaling text or controls. Never combine the platform dialog offset with a second full keyboard-height translation.

## 6. Motion rhythm

- Playback, pause, seeking, and track changes respond immediately.
- Favorites, volume, and selection feedback use 100–160 ms.
- Cards and page transitions typically use 180–260 ms with `easeOutCubic`.
- Menus animate only their own opacity and transform; they must not re-blur the entire page.
- Wallpaper effects prioritize harmony and performance. A static background is better than an unsuitable effect.

## 7. Performance boundary

Avoid decoding wallpaper images repeatedly, rebuilding large `BackdropFilter` regions, destroying video textures, or triggering page-wide `setState` during frequent input. Keep Windows native video output mounted; coordinate audio/MV changes through media state rather than recreating the video surface.

---

## 简体中文

**[English](#interaction-and-motion-guidelines)** · 简体中文 · [文档索引](../README.md#简体中文)

### 1. 视觉目标

Sona 的液态玻璃不是单纯提高透明度。每个表面同时具备主题派生底色、可见边界、稳定对比度和克制的层次感。亮色主题不能变成突兀白块，深色主题也不能用过重阴影压暗内容。

- 内容卡片使用主题派生的玻璃底色、细描边和有限阴影。
- 当前选中态必须明显区别于普通状态，不能只依赖与主题接近的填充色。
- 歌名、歌手、播放次数与类型标签保持清晰层级。
- 自定义壁纸根据实际背景亮度调整前景对比，而不是只按主题名称判断。

### 2. 桌面键鼠规则

- 左键歌曲：播放，并以当前可见列表建立新队列。
- 右键歌曲：菜单从鼠标附近弹出，并自动避开窗口边缘。
- 高频菜单保持紧凑；危险操作独立分组并写清影响范围。
- 播放队列从侧边柔和展开，不改变播放状态，也不截断主内容。
- 音量按钮单击切换静音；悬停显示竖向滑条，鼠标移入滑条后不能提前收起。

### 3. 播放控制排列

控制区围绕播放/暂停保持视觉对称。上一首和下一首紧邻中心控制；循环、队列、收藏和音量在所有页面保持一致的相对顺序。切歌时标题、封面、MV/唱片能力、时长和队列高亮必须同步更新。

### 4. 响应式布局

- 覆盖小窗口、常规桌面窗口和最大化状态，而不是只适配单一截图尺寸。
- 根据可用宽高和断点决定列数、间距与卡片宽度。
- 图片等比缩放，不通过固定宽度拦腰裁断。
- 标题可合理省略，但关键数值和主要操作必须可见。
- 侧栏只保留一个滚动容器：头部与账户入口固定，中间导航独立滚动。

### 5. 键盘避让

手机端登录、注册和编辑表单呼出键盘时，弹窗应柔和让位，内容可以滚动，主要操作始终可点。Material 对话框优先使用自身避让；自定义对话框可用 240 ms 的 `easeOutCubic`，配合 `AnimatedSize`、`SafeArea` 和可滚动表单。只移动容器，不缩放文字与按钮，也不能重复叠加两套键盘位移。

### 6. 动效节奏

- 播放、暂停、切歌和拖动进度立即响应。
- 收藏、音量和选中状态使用 100–160 ms 轻反馈。
- 卡片和页面过渡通常使用 180–260 ms 的 `easeOutCubic`。
- 菜单只动画自身透明度与位移，不让整页重新模糊。
- 壁纸特效优先和谐与性能；没有合适特效时宁可保持静态。

### 7. 性能边界

高频交互中避免重复解码壁纸、重建大范围 `BackdropFilter`、销毁视频纹理或触发整页 `setState`。Windows 原生视频输出保持稳定挂载，音频/MV 切换通过媒体状态协调，而不是反复重建视频表面。
