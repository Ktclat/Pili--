# 开发与构建

[返回首页](../README.md) · [参与贡献](../CONTRIBUTING.md) · [验证记录](VALIDATION.md) · [来源与致谢](ACKNOWLEDGEMENTS.md)

Pili-- 是基于 PiliPlus 独立维护的个人兴趣项目。当前开发和验收重点是 **Android**。本文依据主分支提交 `53f5836` 的构建配置整理；尚未合并的功能分支不作为已支持能力。后续调整以同一提交中的源码、脚本和工作流为准。

## 1. 环境要求

| 工具 | 当前要求与依据 |
| --- | --- |
| Git | 获取项目、Flutter 和固定提交的 Git 依赖 |
| PowerShell | **PowerShell 7**；Windows 和 Linux 均可通过 `pwsh` 运行准备脚本 |
| Flutter | **3.47.8**，安装到本项目 `.tools/flutter`；准备脚本校验提交 `737ba8f885dc774b53b442759999a312c9461e4e` |
| Dart | 使用上述 Flutter 自带的 Dart；`pubspec.yaml` 要求 `>=3.13.0` |
| Java | **JDK 17**，与 Android 编译设置和 CI 一致 |
| Android SDK | Platform **37**、相应构建工具和 Platform-Tools；NDK 版本由 Flutter 的 `ndkVersion` 确定 |
| Linux 主机库 | 执行原生回归测试还需要 `clang`、`pkg-config`、`libgtk-3-dev`、`libx11-dev`、`libxi-dev` |

具体配置见 [pubspec.yaml](../pubspec.yaml)、[Android 构建配置](../android/app/build.gradle.kts) 和 [CI 工作流](../.github/workflows/build.yml)。`compileSdk` 与 `targetSdk` 均为 37；最低 Android 版本由 `flutter.minSdkVersion` 决定，请以实际 APK 的 Manifest 为准。Gradle 使用仓库指定的 Wrapper，无需另装或任意升级全局 Gradle。

### 为什么要隔离 Flutter？

项目继承了上游对 Flutter 和 `material_ui` 的框架补丁，普通的全局 Flutter 环境不能直接替代。准备脚本只接受当前项目的 `.tools/flutter`，并把 Pub 缓存设为 `.tools/pub-cache`，避免修改其他项目使用的 SDK 和包缓存。

## 2. 获取源码并准备依赖

以下命令在 **PowerShell 7** 中执行，适用于 Windows 和已安装相应工具的 Linux 主机：

```powershell
git clone https://github.com/Ktclat/Pili--.git
Set-Location Pili--
git clone --depth 1 --branch 3.47.8 https://github.com/flutter/flutter.git .tools/flutter
./scripts/prepare_android.ps1

$env:PUB_CACHE = Join-Path $PWD '.tools/pub-cache'
$flutter = Join-Path $PWD '.tools/flutter/bin/flutter'
if ($IsWindows) { $flutter += '.bat' }
& $flutter doctor -v
```

准备脚本报错时先解决错误，再继续后续步骤。如果 SDK 已存在，先检查其版本和提交，不要再次克隆到同一路径。Android SDK 的位置和许可须在本机配置完成；缺少 SDK 许可时可使用上述隔离 Flutter 执行 `doctor --android-licenses`。

[`prepare_android.ps1`](../scripts/prepare_android.ps1) 会执行以下工作：

1. 校验隔离 SDK 路径和固定提交，设置项目内 Pub 缓存。
2. 运行 `flutter pub get`，按 `pubspec.yaml` 和 `pubspec.lock` 解析依赖。
3. 检查并应用 [`lib/scripts/`](../lib/scripts/) 中的 Flutter 与 `material_ui` 补丁；已应用的补丁会跳过，不匹配则停止。
4. 调用 [`fetch_native_libs.ps1`](../scripts/fetch_native_libs.ps1)，下载三个 Android ABI 的媒体库并验证脚本内固定的 SHA-256。

准备过程需要联网，也会修改本项目的 SDK、包缓存和构建目录。保留 `pubspec.lock`；无意升级依赖时，应检查并撤销意外的锁文件变动，不能用 `pub upgrade` 代替准备步骤。清理 `build/` 后若媒体库需要重新获取，可再次运行准备脚本。

### Linux 主机补充

Debian / Ubuntu 上安装原生测试依赖的命令与 CI 一致：

```bash
sudo apt-get update
sudo apt-get install -y --no-install-recommends clang pkg-config libgtk-3-dev libx11-dev libxi-dev
pwsh
```

随后在打开的 PowerShell 中执行上面的准备步骤。若从 Bash 使用 `pwsh -File scripts/prepare_android.ps1`，脚本设置的环境变量不会回传给 Bash；后续 Flutter 命令应显式设置 `PUB_CACHE`，或继续在同一个 PowerShell 会话中操作。

## 3. 静态检查与 Android 构建

在完成准备的 PowerShell 会话中执行：

```powershell
& $flutter analyze --no-pub --no-fatal-infos
if ($LASTEXITCODE -ne 0) { throw '静态检查失败。' }
& $flutter test --no-pub
if ($LASTEXITCODE -ne 0) { throw '回归测试失败。' }

$version = [regex]::Match((Get-Content pubspec.yaml -Raw), '(?m)^version:\s*([0-9.]+)\+([0-9]+)\s*$')
if (-not $version.Success) { throw '请检查 pubspec.yaml 中的 version。' }
$versionName = $version.Groups[1].Value
$versionCode = $version.Groups[2].Value
$revision = (git rev-parse HEAD).Trim()
$buildTime = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()

& $flutter build apk --release --split-per-abi --no-pub `
  "--dart-define=pili.name=$versionName" `
  "--dart-define=pili.code=$versionCode" `
  "--dart-define=pili.hash=$revision" `
  "--dart-define=pili.time=$buildTime"
if ($LASTEXITCODE -ne 0) { throw 'APK 构建失败。' }
```

APK 输出目录为 `build/app/outputs/flutter-apk/`，按 ABI 区分 `armeabi-v7a`、`arm64-v8a` 和 `x86_64`。选择与设备 ABI 匹配的包。

Android 的版本名、版本号来自 `pubspec.yaml`；上面的 `pili.*` 参数用于 [`BuildConfig`](../lib/build_config.dart) 中的应用展示和构建来源。它们不会代替 Android 的 `--build-name` / `--build-number`。如果覆盖 Android 版本，须同步传入相同的 `pili.name` / `pili.code`。正式打包前先提交源码，避免把含未提交修改的包标注成某个干净提交。

`analyze --no-fatal-infos` 允许现存 info 级提示，以 error / warning 阻断检查；它不表示没有技术债。回归测试、编译通过与安装后验收是不同层面的结果，历史执行记录见 [VALIDATION.md](VALIDATION.md)。

## 4. 签名、安装身份与发布

当前 Gradle 配置会读取 `android/key.properties`。该文件不存在或没有 `storeFile` 时，**release 构建也使用 debug 测试签名**。文件名中的 `release` 表示编译模式，不代表正式签名或完成发布验收。

正式分发应配置自己的签名密钥，并在本机创建以下文件，填入真实值：

```properties
# android/key.properties（仅保存在本机）
storeFile=/absolute/path/to/piliminus-release.jks
storePassword=<自己的密钥库密码>
keyAlias=<自己的别名>
keyPassword=<自己的密钥密码>
```

推荐把密钥保存在仓库之外。Windows 的 `storeFile` 可使用 `C:/.../piliminus-release.jks` 形式的绝对路径。仓库已忽略 `key.properties` 和常见密钥文件，但提交前仍应检查暂存区。配置自有签名后，当前 Gradle 设置也会把它应用到其他构建类型。

| 项目 | 当前值 / 行为 |
| --- | --- |
| Android 正式 applicationId | `io.github.ktclat.piliminus` |
| Debug applicationId | `io.github.ktclat.piliminus.debug` |
| Android namespace / JNI 类路径 | 保留 `com.example.piliplus`，与安装包身份用途不同 |
| Dart 包名 | 保留 `PiliPlus`，现有 `package:PiliPlus/...` 导入依赖它 |
| CI 附件 | `Pili--Android-test-signed`；测试产物，当前保留 14 天 |

因此，整理项目品牌时不要批量替换源码中的 `PiliPlus` 或 `com.example.piliplus`。名称、applicationId、Java/JNI 类路径和 Dart 导入名需要分别评估。与上游共存还应实际检查快捷方式、外部链接和账号数据隔离；不同 applicationId 本身不能代替完整验收。

当前 [工作流](../.github/workflows/build.yml) 由 `main` 分支推送或手动触发，运行分析、测试和 APK 构建，然后上传测试签名附件。请以具体运行记录为准，不把附件存在视为正式版本发布。正式版本还应提供版本说明、对应源码、构建信息及校验值，保留 [LICENSE](../LICENSE) 和 [NOTICE](../NOTICE)。

## 5. 常见构建问题

### Windows 路径包含空格

Dart 原生构建钩子在带空格的 SDK 路径下可能启动失败。优先使用没有空格的项目路径；也可映射到一个**尚未占用**的盘符：

```powershell
subst P: "D:\Projects With Spaces\Pili--"
Set-Location P:\
./scripts/prepare_android.ps1
$env:PUB_CACHE = 'P:\.tools\pub-cache'
$flutter = 'P:\.tools\flutter\bin\flutter.bat'
```

映射不移动源码。切换项目路径后重新运行准备脚本，以更新生成的依赖路径；结束所有构建进程并离开 `P:` 后，再按需使用 `subst P: /d` 删除映射。不要覆盖已使用的盘符。

### 框架补丁无法应用

确认使用指定 SDK 提交和本项目的 Pub 缓存，检查失败补丁对应的文件与日志。不要把补丁强行应用到共享 SDK，也不要通过忽略错误继续构建。升级 Flutter 或 `material_ui` 时需要逐个复核补丁，不能仅修改版本号。

### 原生库下载失败或校验不符

查看 [`fetch_native_libs.ps1`](../scripts/fetch_native_libs.ps1) 中固定的下载来源和版本，排查连接后重新运行准备脚本。校验值不符应核实源文件；不要删除校验步骤，也不要通过关闭 TLS 校验解决下载问题。

## 6. 代码与工具入口

| 路径 | 用途 |
| --- | --- |
| `lib/pages/` | 页面与交互，包括扫码、会员购等入口 |
| `lib/http/` | API、请求与重试逻辑 |
| `lib/utils/accounts/` | 账号、Cookie 及请求身份管理 |
| `lib/utils/android/` | Android 桥接及生成的 JNI 绑定 |
| `lib/scripts/` | 继承的 Flutter / 依赖补丁 |
| `android/` | Android 宿主、Manifest、资源和打包配置 |
| `scripts/` | 环境准备、媒体库获取和安装后采证工具 |
| `tool/` | JNI 代码生成；使用前阅读 [工具说明](../tool/README.md) |
| `test/` | 回归测试 |
| `docs/validation/` | 已提交的历史验收截图与记录 |
| `ios/`、`macos/`、`linux/`、`windows/` | 保留的上游平台代码，当前不作完整验证承诺 |

[`android_acceptance.py`](../scripts/android_acceptance.py) 可操作已安装 APK、生成二维码测试素材并保存真实界面证据。它需要 Python、ADB 和指定设备；`fixtures` 还需要 `qrcode`、`Pillow`，并会向设备图片目录写入素材。操作示例和验收边界见 [验证记录](VALIDATION.md)。提交截图或日志前检查账号、Cookie、手机号及订单信息。

## 7. 同步上游

Pili-- 可以按自己的需求迭代；同步上游时仍应保留可追溯的作者、提交和许可证信息。

```bash
git remote add upstream https://github.com/bggRGjQaUbCoE/PiliPlus.git
git fetch upstream
```

如果已有 `upstream`，先用 `git remote -v` 核对地址，不必重复添加。阅读差异后，在单独分支选择性合入；对选取的提交可使用 `git cherry-pick -x <提交号>` 记录来源，合并较大范围时保留原提交历史并说明冲突处理。同步后重新审阅框架补丁、Android 身份、账号请求策略和本项目新增功能，执行相应验证。

不要为了让 Contributors 列表看起来只属于本项目而改写原作者或删除历史。贡献归属和独立维护关系见 [来源与致谢](ACKNOWLEDGEMENTS.md)。
