# Android player acceptance / Android 播放器验收

Sona treats background playback as a release requirement, not an optional UI
smoke test. Run the automated script first, then record the four physical tests
below for every release candidate.

```powershell
.\tool\mobile_player_regression.ps1 -Serial <device-serial> `
  -ExpectedVersionName 0.5.0 -ExpectedVersionCode 2080 `
  -ExerciseMediaButtons -ExerciseRotation -ExerciseNotificationPermission
```

The script never uninstalls Sona and never clears app data. Any notification
permission or rotation setting it changes is restored in `finally`. Reports are
written to the ignored `artifacts/mobile-regression/` directory.

The default invocation is intentionally conservative: it only reads the current
notification-permission and rotation state, while still exercising the Android
trim-memory callback and force-stop/relaunch recovery. Media buttons, forced
rotation and temporary notification-permission denial require their explicit
switches. Do not enable those switches while a user is actively listening or
when a non-mutating release audit was requested.

For a release gate, always pass both expected-version arguments. Without them,
the script intentionally remains useful as a generic device diagnostic but does
not prove that the intended release candidate is installed. The installed app
must also be non-debuggable.

## Automated evidence

- Installed version and required wake-lock/foreground-service declarations.
- Cold launch, HOME/background survival and media-session publication.
- Optional media-button round trip.
- Current notification-permission state; optional denied-permission launch,
  followed by restoration when `-ExerciseNotificationPermission` is supplied.
- Optional portrait/landscape recreation with the original rotation setting
  restored afterward.
- Android critical-memory callback, force-stop/relaunch recovery and crash log.

## Physical evidence required

Automation cannot honestly replace these checks:

1. Start a track, turn the screen off for at least ten minutes, then verify
   uninterrupted audio, correct lock-screen metadata and progress.
2. Connect a physical Bluetooth headset and verify play/pause, next, previous,
   disconnect/reconnect and volume behavior.
3. During playback, receive and end a real call. Audio must pause for focus
   loss and follow the documented resume policy after the call.
4. Repeat screen-off/background playback with the phone's battery saver on and
   after removing Sona from recents. Record device model, Android version and
   OEM battery policy.

## 中文说明

自动脚本覆盖冷启动、后台、媒体会话、通知权限拒绝、横竖屏、低内存和强杀
恢复，而且会恢复它修改过的系统设置。蓝牙实体耳机、真实来电、十分钟熄屏
播放和厂商省电策略必须由真实设备验证，不能用模拟结果冒充通过。每次正式
发布都要同时保存自动 JSON 报告和上述四项的人工证据。
