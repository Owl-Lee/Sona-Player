# Windows performance profile / Windows 性能剖析

## English

### Scope

This profile was captured from a Flutter **Profile** build on Windows after the
0.5.0 visual-effects and player lifecycle changes. It separates Dart heap use
from native process memory so a large working set is not incorrectly reported
as a Dart leak.

### Observations

| Metric | Result |
| --- | --- |
| Stable working set after launch and several real theme changes | 855.7–856.0 MB |
| Stable private bytes | 924.3–925.3 MB |
| Dart heap used / capacity | 30.8 MB / 33.8 MB |
| Dart external memory | 27 KB |
| Peak working set while decoding a newly selected theme | 1.596 GB |
| 15-second idle CPU delta after settling | 0.01 s |

The theme peak returned to approximately 856 MB instead of growing after every
switch. This is evidence against a continuously growing theme-picker leak. It
does **not** mean the baseline is ideal: most of the remaining memory is outside
the Dart heap and is therefore most likely held by Flutter's compositor,
decoded textures, media_kit, and native audio/video libraries.

### Changes made from the profile

- Added **Full effects**, **Energy saver**, and **Motion off** modes.
- Reduced ambient animation to 12 fps and 52% particle density in Energy saver.
- Disabled ambient tickers and live backdrop blur in Motion off.
- Applied mode-aware image decode/cache budgets.
- Reused one app-wide video-controller wrapper instead of accumulating player
  listeners whenever the now-playing page is opened.
- Limited Windows video output to 1080p in Full mode and 720p in Energy saver.

### Verification and limitation

Automated tests cover 20 consecutive mode changes and persistence. Several real
theme changes were also exercised in Profile mode. A planned 20-cycle desktop
pointer automation run was stopped when concurrent user input appeared, so it
is intentionally **not** reported as completed. A future dedicated session
should record Flutter DevTools native allocations and GPU texture residency
while looping audio-only and 4K MV playback.

## 中文

### 范围

本次使用 Windows Flutter **Profile** 构建，在 0.5.0 的特效档位和播放器生命周期
优化后采样。测试将 Dart 堆与整个原生进程内存分开，避免把较大的工作集直接误判成
Dart 内存泄漏。

### 结果

| 指标 | 结果 |
| --- | --- |
| 启动并实际切换多次皮肤后的稳定工作集 | 855.7–856.0 MB |
| 稳定 private bytes | 924.3–925.3 MB |
| Dart 堆已用 / 容量 | 30.8 MB / 33.8 MB |
| Dart external memory | 27 KB |
| 首次解码新皮肤时的工作集峰值 | 1.596 GB |
| 稳定后 15 秒空闲 CPU 增量 | 0.01 秒 |

换肤峰值随后回落到约 856 MB，没有随着每次换肤持续阶梯式增长，因此目前没有
“换肤持续泄漏”的证据。但基础占用仍偏高；剩余内存绝大部分不在 Dart 堆中，更可能
来自 Flutter 合成层、已解码纹理、media_kit 和原生音视频库。

### 已实施优化

- 新增“完整特效 / 节能特效 / 关闭动态特效”。
- 节能档将环境动画降至 12 fps、粒子密度降至 52%。
- 关闭动态特效时停止环境 ticker，并取消实时背景模糊。
- 图片解码尺寸和缓存预算随性能档切换。
- 全局复用单一视频控制器包装，避免每次进入播放页累积监听器。
- Windows 视频输出在完整档限制为 1080p、节能档限制为 720p。

### 验证边界

自动化测试覆盖了连续 20 次性能档切换与持久化；Profile 窗口也完成了多次真实换肤。
原计划的 20 次鼠标自动换肤过程中检测到用户同时操作，为避免抢夺桌面控制已安全
停止，因此没有虚报为完成。后续应在独立测试时段用 Flutter DevTools 继续记录原生
allocation 和 GPU 纹理驻留，并分别循环音频与 4K MV。
