# Release engineering / 发布工程

English is authoritative for the release process. The Chinese section below
mirrors every safety-critical requirement.

## Release outputs

Every public tag must produce exactly these stable assets. The website depends
on these names and may not be changed without updating its download links.

- `Sona-Android.apk`
- `Sona-Android.apk.sha256`
- `Sona-Windows-x64.zip`
- `Sona-Windows-x64.zip.sha256`
- `Sona-Windows-x64-Setup.exe`
- `Sona-Windows-x64-Setup.exe.sha256`

The release gate rejects missing files, extra files, malformed sidecars,
checksum mismatches, incomplete Windows ZIPs, and any tag/version mismatch.
All GitHub Actions and the actionlint container are pinned to immutable commit
SHAs or an image digest; updates must be reviewed and intentional.

The only public release target is `Owl-Lee/Sona-Player`. The workflow refuses
to publish from a private development mirror, because assets released there
would not be anonymously downloadable. Configure secrets and create the
release tag in the public repository only.

## Required GitHub Actions secrets

Configure these repository secrets before creating a release tag:

- `SONA_ANDROID_KEYSTORE_BASE64`
- `SONA_ANDROID_STORE_PASSWORD`
- `SONA_ANDROID_KEY_PASSWORD`
- `SONA_ANDROID_KEY_ALIAS`
- `SONA_ACOUSTID_API_KEY`

Encode the keystore as one uninterrupted Base64 string. Never commit the
keystore, `android/key.properties`, passwords, or a `.env` file. The AcoustID
application key is injected at build time so it does not appear in source or CI
logs; as with any client-side application identifier, it can still be recovered
from a distributed binary and must never be treated as a server-side secret.

The expected permanent Android signing certificate SHA-256 is:

`1F:60:07:D8:1E:BF:42:3D:4E:BD:1A:A1:65:8C:21:0D:40:24:1C:87:9C:97:B7:C1:64:B2:33:B5:C1:39:9B:BD`

The workflow fails unless the finished APK has this exact certificate,
application ID `com.sonarvault.sonar_vault`, version name, and version code.
Store at least two encrypted offline copies of the permanent keystore. Losing
it makes upgrades over existing installations impossible.

## Version and release flow

1. Set `pubspec.yaml` to `x.y.z+build` and `MyAppVersion` in
   `installer/windows/Sona.iss` to the same `x.y.z` value.
2. Run `pwsh ./tool/release_gate.ps1`, formatting, analysis, and all tests.
3. Merge only after every CI job passes, including gitleaks and both platform
   build smoke tests.
4. Tag the exact tested commit with the exact version, for example `v0.5.0`.
   A tag such as `v0.5`, `0.5.0`, or a tag that differs from `pubspec.yaml`
   fails before release builds start.
5. The release workflow restores signing material only on the ephemeral runner,
   builds both platforms, validates identities and complete payloads, generates
   SHA-256 sidecars, removes signing files, then publishes the fixed asset set.
6. In a private/incognito browser, anonymously download all three binaries and
   their sidecars from GitHub Releases. Verify the hashes, Android certificate,
   clean installation, and upgrade over the previous public version on real
   Windows and Android devices.

For a local final asset audit, place all six files in one directory and run:

```powershell
pwsh ./tool/release_gate.ps1 `
  -Tag v0.5.0 `
  -ArtifactSet all `
  -ArtifactDirectory path/to/release-assets
```

Windows binaries are not Authenticode-signed yet and may show Microsoft
SmartScreen's **Unknown publisher** warning. Never describe the Windows ZIP or
installer as signed. The Android APK is release-signed with the permanent Sona
certificate.

## 中文

### 固定发布资产

每个公开版本必须且只能发布下面六个固定名称的文件；官网的下载链接依赖这些
名称，不能单独改名：

- `Sona-Android.apk` 与 `Sona-Android.apk.sha256`
- `Sona-Windows-x64.zip` 与 `Sona-Windows-x64.zip.sha256`
- `Sona-Windows-x64-Setup.exe` 与
  `Sona-Windows-x64-Setup.exe.sha256`

发布门禁会拒绝缺失或多余文件、错误的校验文件、SHA-256 不匹配、不完整的
Windows ZIP，以及标签、Flutter 版本和安装器版本不一致。
GitHub Actions 与 actionlint 容器均固定到不可变提交 SHA 或镜像摘要；升级
依赖时必须人工审查后再更新。

唯一正式公开发布仓库是 `Owl-Lee/Sona-Player`。工作流会拒绝从私有开发镜像
发布，否则安装包无法被陌生用户匿名下载。只在公开仓库配置 Secrets 并创建
正式版本标签。

### GitHub Secrets 与永久签名

打标签前，在仓库 Actions Secrets 中配置上面列出的五项。永久 keystore、
`android/key.properties`、密码和 `.env` 绝不能提交；AcoustID 应用 Key 由
工作流构建时注入，不写进源码或日志，但客户端标识仍可能从安装包中提取，不能
把它当作服务端机密。

工作流不仅打印证书，还会强制核对成品 APK 的永久证书 SHA-256、应用 ID、
版本名和版本号。永久 keystore 至少保留两份离线加密备份；一旦丢失，已安装
用户将无法覆盖升级。

### 发布步骤

1. `pubspec.yaml` 写成 `x.y.z+build`，Inno 的 `MyAppVersion` 同步为
   `x.y.z`。
2. 本地运行 `pwsh ./tool/release_gate.ps1`，并通过格式化、静态分析和全部测试。
3. 只有 CI 的泄密扫描、测试及 Android/Windows 构建都通过后才合并。
4. 对同一个已测试提交创建完全一致的标签，例如 `v0.5.0`；任何不规范或版本
   不一致的标签都会在构建前失败。
5. 工作流只在临时 runner 中还原签名，完成身份、资产和哈希验证后清除签名
   文件，再发布固定资产。
6. 发布后用无痕窗口匿名下载全部文件，核对哈希与 Android 证书，并在真实
   Windows、Android 设备完成全新安装和覆盖升级。

Windows 当前没有 Authenticode 代码签名，安装器可能触发 SmartScreen
“未知发布者”提示；必须如实说明，不能宣称 Windows 已签名。Android APK
则使用 Sona 永久证书正式签名。
