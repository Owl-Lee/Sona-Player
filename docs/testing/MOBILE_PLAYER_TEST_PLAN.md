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

## Manual 0.5.0 acceptance checklist

Record the device or machine, date, result, and a screenshot or short note for
every row. Use expendable test tracks for destructive cloud checks.

| Area | Manual procedure | Pass criteria | Result |
| --- | --- | --- | --- |
| Android screen off | Play one track, lock the screen for at least 10 minutes, then use lock-screen pause/next. | Audio is uninterrupted; title, progress, pause and next stay correct. | ☐ |
| Android background | Play, switch between several apps, remove Sona from recents, then reopen it. | Playback and the current queue survive according to the documented background policy. | ☐ |
| Bluetooth controls | Connect a physical headset and test play/pause, next, previous, volume, disconnect and reconnect. | Every action happens once; metadata follows the audible track; no crash or stuck session. | ☐ |
| Real phone call | Receive and end a real call while music is playing. | Sona yields audio focus and follows the expected resume policy after the call. | ☐ |
| Permission denial | Deny notification permission, start playback, close and reopen Sona. | Playback still works and the permission prompt is not repeatedly shown. | ☐ |
| Rotation and memory | Rotate during playback, enable battery saver, trigger low-memory conditions, then return to Sona. | Layout remains usable and the current track/queue recover without a black screen. | ☐ |
| Android upgrade | Install the official 0.5.0 APK over an official 0.4.51 installation. | The install succeeds in place and the library, settings and playlists remain. | ☐ |
| Windows install/upgrade | Install with the x64 Setup package, then upgrade or reinstall the same version. | Sona starts, user data remains, and uninstall information is correct. SmartScreen may show the documented Unknown publisher warning. | ☐ |
| Windows performance | In Profile mode, switch themes 20 times and alternate Full/Energy saver/Motion off. | Memory returns near its post-start plateau, controls remain responsive, and effects match the chosen mode. | ☐ |
| Playback stress | Rapidly press next/previous, change queues, switch audio/MV, and delete a disposable current track/MV. | Audible media, metadata, progress, queue highlight and player surface always converge on one track. | ☐ |
| Complete backup | Export a `.sonabackup` to an external folder, restore it into a safe test installation, and play samples. | Songs, MVs, playlists, metadata history and managed images restore; corrupt or incomplete backups are rejected. | ☐ |
| Cloud recycle bin | With disposable cloud tracks, delete, undo, restore, permanently delete and empty the bin. | The 30-day state is correct, local files are never removed, and other signed-in devices converge after refresh. | ☐ |
| Offline recovery | Start playback offline, reconnect, then retry cloud refresh and identification. | Local playback stays usable; failures are clear; reconnect does not duplicate or erase data. | ☐ |

## 中文说明

自动脚本覆盖冷启动、后台、媒体会话、通知权限拒绝、横竖屏、低内存和强杀
恢复，而且会恢复它修改过的系统设置。蓝牙实体耳机、真实来电、十分钟熄屏
播放和厂商省电策略必须由真实设备验证，不能用模拟结果冒充通过。每次正式
发布都要同时保存自动 JSON 报告和上述四项的人工证据。

上方表格是 0.5.0 的人工验收清单。每项请记录设备或电脑、日期、结果和一张
截图或简短说明；云端删除、回收站及恢复测试必须使用可丢弃的测试歌曲，不能
对唯一副本做破坏性验证。
