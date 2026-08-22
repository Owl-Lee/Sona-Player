# Development and Maintenance Guide

**English** · [简体中文](#简体中文) · [Documentation index](../README.md)

## 1. Getting started

```powershell
flutter pub get
flutter analyze
flutter test
flutter run -d windows
```

Windows release build:

```powershell
flutter build windows --release
```

Android APK:

```powershell
flutter build apk --release
```

Android release builds require your own local `android/key.properties` and keystore. The official Sona release key is deliberately never stored in this repository; contributors should use a separate development or test key and must not distribute builds as official Sona packages. The repository also does not store a local Flutter SDK path, desktop shortcuts, or machine-specific build paths. Configure those in your own toolchain.

## 2. Configuration boundary

The public client may contain only public, client-safe configuration. Never commit:

- database passwords;
- Supabase `service_role` or other secret keys;
- object-storage private keys;
- real AcoustID, third-party service, or signing-certificate secrets;
- user email addresses, accounts, real media paths, or private media samples.

Inject optional services through `--dart-define` or a controlled build environment. Logs and user-facing errors must never echo secret values.

## 3. Changing playback

Playback changes must cover:

- authoritative current track and queue source;
- audio/MV capability detection;
- position and pause-state preservation;
- automatic next;
- deletion of the current item;
- navigation and player expansion/collapse;
- Windows video-texture lifecycle.

Do not let pages keep independent long-lived playback states, and do not repeatedly destroy the video widget to work around first-frame behavior.

## 4. Changing the data model

- Schema changes require repeatable migrations.
- New fields require defaults or a migration strategy for existing data.
- Track deletion must clean every relationship.
- Cloud fields stay separate from local playback fields so local core data remains writable offline.
- Preserve original metadata or reversible history before smart identification changes display values.

## 5. Changing the UI

At minimum, verify:

- light/dark and cool/warm themes;
- compact and maximized windows;
- Windows mouse and keyboard;
- Android narrow screens and soft keyboard;
- Simplified Chinese, Traditional Chinese, and English;
- empty lists, long titles, unknown artists, and missing artwork.

All UI copy belongs in localization resources—not only settings, but also menus, notifications, empty states, and confirmation dialogs. Titles, artists, and albums are user data; changing interface language should not fabricate translations, although online results may select a Simplified Chinese, Traditional Chinese, or English alias according to user preference.

## 6. Commits and verification

Keep each commit focused and describe the user-visible outcome. Stage only files belonging to the current task. Before release, run static analysis and tests, then use the [reliability test matrix](../testing/reliability-checklist.md) for real-window regression on affected high-risk paths.

---

## 简体中文

**[English](#development-and-maintenance-guide)** · 简体中文 · [文档索引](../README.md#简体中文)

### 1. 开始之前

运行上方命令获取依赖、静态分析、执行测试并启动 Windows 版。发布构建使用 `flutter build windows --release`，Android APK 使用 `flutter build apk --release`。Android Release 构建需要自行在本机配置 `android/key.properties` 与 keystore；Sona 官方发布私钥不会进入公开仓库，贡献者应使用独立的开发或测试签名，也不能把自行构建的包冒充官方版本分发。仓库同样不保存本机 Flutter SDK、桌面快捷方式或构建机绝对路径，请在自己的工具链中配置。

### 2. 配置边界

公开客户端只允许包含面向客户端的公开配置。不得提交数据库密码、Supabase `service_role` 或其他 secret key、对象存储私钥、AcoustID/第三方服务/签名证书的真实秘密，以及用户邮箱、账号、真实媒体路径或私人媒体样本。可选服务通过 `--dart-define` 或受控构建环境注入，日志和错误提示也不得回显秘密值。

### 3. 修改播放逻辑

播放改动必须同时检查当前曲目与队列来源、音频/MV 能力识别、进度与暂停保持、自动下一首、删除当前项、页面切换与播放器展开/收起，以及 Windows 视频纹理生命周期。不要让页面维护独立的长期播放状态，也不要通过反复销毁视频 widget 解决首帧问题。

### 4. 修改数据模型

- Schema 变化需要可重复执行的迁移。
- 新字段必须为旧数据提供默认值或迁移策略。
- 删除曲目时处理所有引用关系。
- 云同步字段与本地播放字段分离，离线时仍能读写本地核心数据。
- 智能识别修改展示资料前，保留原始媒体信息或可撤销历史。

### 5. 修改界面

至少验证亮/暗与冷/暖主题、小窗口与最大化、Windows 键鼠、Android 窄屏与软键盘、简体中文/繁體中文/English，以及空列表、长标题、未知歌手和缺少封面。所有 UI 文案都进入本地化资源，不能遗漏菜单、提示、空状态或确认对话框。歌曲、歌手和专辑属于用户数据；切换界面语言不应伪造翻译，但在线识别可以按偏好选择简体、繁体或英文别名。

### 6. 提交与验证

提交保持单一目的并说明用户可见结果，只暂存当前任务文件。发布前运行静态分析和测试，再按[稳定性测试矩阵](../testing/reliability-checklist.md#简体中文)对相关高风险路径做真实窗口回归。
