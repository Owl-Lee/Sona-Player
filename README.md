# Sona

> A local-first, offline-ready music player for Windows and Android.

[Website](https://owl-lee.github.io/Sona-Player/?lang=en) · [Download](https://github.com/Owl-Lee/Sona-Player/releases/latest) · [Report an issue](https://github.com/Owl-Lee/Sona-Player/issues) · [简体中文](#chinese--简体中文)

![Sona immersive vinyl player](docs/site/assets/screenshots/player.png)

Sona is made for people who keep their own music files. Import, organize and play your music and MVs without depending on an online catalog or an always-on connection. The interface combines liquid-glass surfaces, an immersive vinyl player and theme-aware visuals with a practical local library.

## Highlights

- **Local-first playback** — your library, playlists, favorites, queue and history remain usable offline.
- **Music and MVs together** — manage audio and local video through one consistent playback flow.
- **Smart metadata cleanup** — use media tags, filename parsing and MusicBrainz, with optional Chromaprint / AcoustID fingerprint matching on Windows.
- **A library that feels personal** — favorites, playlists, recents, listening charts and expressive text covers.
- **Theme-aware design** — liquid glass, vinyl playback, adaptive contrast and multiple wallpaper effects.
- **Three interface languages** — Simplified Chinese, Traditional Chinese and English.

## Download

| Platform | Package | Notes |
| --- | --- | --- |
| Windows 10 / 11 | [Download ZIP](https://github.com/Owl-Lee/Sona-Player/releases/latest/download/Sona-Windows-x64.zip) | 64-bit portable build |
| Android | [Download APK](https://github.com/Owl-Lee/Sona-Player/releases/latest/download/Sona-Android.apk) | Direct install; development-signed preview |

The current release is a public preview. Download builds only from this repository or the [official Sona website](https://owl-lee.github.io/Sona-Player/?lang=en).

## Technology

| Area | Stack |
| --- | --- |
| Client | Flutter / Dart · Windows + Android |
| State management | Riverpod |
| Local data | SQLite · FFI on Windows, sqflite on mobile |
| Audio and video | media_kit, audio_service, audio_session |
| Media import | file_picker, audio_metadata_reader |
| Optional sync foundation | Supabase |

## Build from source

```powershell
flutter pub get
flutter analyze
flutter run -d windows
```

Optional AcoustID lookup can be enabled with a free application key:

```powershell
flutter build windows --release --dart-define=ACOUSTID_API_KEY=YOUR_APPLICATION_KEY
```

Without an AcoustID key, track identification still uses local tags, filename cleanup and the free MusicBrainz public database. Candidate metadata is presented for confirmation rather than silently overwriting the library.

## Privacy and product scope

Sona is not a music distribution service and does not provide copyrighted tracks. Your local files remain on your device unless you explicitly use an optional sync feature. Cloud services enhance the experience; they are not required for local playback.

## Chinese / 简体中文

<details>
<summary><strong>展开中文介绍 / View Chinese summary</strong></summary>

<br>

Sona 是一款面向 Windows 和 Android 的本地优先音乐播放器。它用于导入、整理和播放你自己拥有的音乐与 MV，不依赖在线曲库，断网时本地曲库、歌单、收藏、播放队列和记录仍然可用。

主要功能包括：

- 音乐与本地 MV 的统一管理和播放；
- 标签、文件名、MusicBrainz 与可选音频声纹识别；
- 收藏、歌单、最近播放、听歌排行和播放队列；
- 液态毛玻璃、黑胶播放页、多套壁纸与主题特效；
- 简体中文、繁體中文与 English 界面；
- Windows 桌面端与 Android 窄屏适配。

[访问中文官网](https://owl-lee.github.io/Sona-Player/) · [下载最新版本](https://github.com/Owl-Lee/Sona-Player/releases/latest) · [提交问题](https://github.com/Owl-Lee/Sona-Player/issues)

</details>
