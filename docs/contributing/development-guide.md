# Development and Maintenance Guide / 开发与维护指南

## 1. 开始之前

```powershell
flutter pub get
flutter analyze
flutter test
flutter run -d windows
```

Windows Release：

```powershell
flutter build windows --release
```

Android APK：

```powershell
flutter build apk --release
```

本仓库不保存本机 Flutter SDK 路径、个人桌面快捷方式或构建机绝对路径。请使用自己的工具链配置。

## 2. 配置边界

公开客户端只允许包含面向客户端的公开配置。下面内容不得提交：

- 数据库密码；
- Supabase `service_role` / secret key；
- 对象存储私钥；
- AcoustID、第三方服务或签名证书的真实密钥；
- 用户邮箱、账号、真实文件路径或媒体样本。

可选服务通过 `--dart-define` 或受控构建环境注入。日志和错误提示也不得回显秘密值。

## 3. 修改播放逻辑

播放相关改动必须同时检查：

- 当前曲目与队列来源；
- 音频/MV 能力识别；
- 进度与暂停状态保持；
- 自动下一首；
- 删除当前项；
- 页面切换与播放器展开/收起；
- Windows 视频纹理生命周期。

不要让页面维护独立的长期播放状态，也不要通过反复销毁视频 widget 解决首帧问题。

## 4. 修改数据模型

- Schema 变化需要可重复执行的迁移。
- 新字段必须为旧数据提供默认值或迁移策略。
- 删除曲目时处理所有引用关系。
- 云同步字段与本地播放字段分离，云端不可用时仍能读写本地核心数据。
- 保存展示名称时保留原始媒体信息或可撤销历史，避免智能识别不可逆覆盖。

## 5. 修改界面

至少验证：

- 亮/暗、冷/暖主题；
- 小窗口与最大化；
- Windows 键鼠；
- Android 窄屏与软键盘；
- 简体中文、繁體中文与 English；
- 空列表、长标题、未知歌手和缺少专辑图。

UI 文案必须进入本地化系统，不能只翻译设置页而漏掉菜单、Toast、空状态或确认对话框。歌曲、歌手和专辑属于用户数据；界面语言变化不应伪造翻译，但在线识别结果可按语言偏好选择简体、繁体或英文别名。

## 6. 提交与验证

提交应保持单一目的，明确写出用户可见结果。只暂存当前任务文件。发布前运行静态分析和测试，并按 [稳定性测试矩阵](../testing/reliability-checklist.md) 对相关高风险路径做真实窗口回归。

[Back to documentation index](../README.md)
