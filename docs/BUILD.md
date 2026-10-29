# Android 构建指南

[文档索引](README.md) · [安装测试包](INSTALL.md)

## 环境与构建

需要 Git、PowerShell 7、JDK 17、Android SDK 37。上游依赖 Flutter 框架补丁，必须使用项目内隔离环境：

```powershell
git clone https://github.com/Ktclat/Pili--.git
cd Pili--
git clone --depth 1 --branch 3.47.8 https://github.com/flutter/flutter.git .tools/flutter
./scripts/prepare_android.ps1
$env:PUB_CACHE = Join-Path $PWD '.tools/pub-cache'
./.tools/flutter/bin/flutter analyze --no-pub --no-fatal-infos
./.tools/flutter/bin/flutter test --no-pub
./scripts/build_android.ps1
```

输出在 `build/app/outputs/flutter-apk/`。准备脚本校验 SDK 提交、使用独立 Pub 缓存、幂等应用补丁，不重置或删除共享 SDK/缓存。默认强制使用已提交的 `pubspec.lock`；主动修改依赖时使用 `./scripts/prepare_android.ps1 -UpdateLockfile`，审阅并提交锁文件差异。

构建脚本从 `pubspec.yaml` 读取版本名与构建号，统一写入 APK 和关于页，并记录源码提交及构建时间。未提交改动的测试包附加 `-dirty` 标记，正式签名模式要求先提交审阅后的源码。可用 `-TargetPlatform android-arm64` 仅构建 ARM64。应用检查更新时比较安装版本与本仓库的稳定 Release 版本；没有正式 Release 时会明确提示。

Linux 主机运行回归测试时，`cnativeapi` 的原生钩子还需要 `clang`、`pkg-config`、`libgtk-3-dev`、`libx11-dev`、`libxi-dev`；CI 已安装这些依赖。

正式分发前配置自己的 `android/key.properties` 和签名密钥，密钥不得提交；使用 `./scripts/build_android.ps1 -RequireReleaseSigning` 检查配置后构建，并长期保管同一签名密钥用于后续升级。未配置时使用测试签名；不同机器或 CI 运行生成的测试密钥可能不同，不能依赖这些包互相覆盖升级。CI APK 是测试产物，构建成功不代表成品验收通过。

## Windows 含空格路径

Dart 原生构建钩子在带空格的 SDK 路径下可能启动失败。可将项目映射到一个**尚未占用**的盘符，再从该盘符运行上述准备和构建命令，例如：

```powershell
subst P: "D:\OneDrive - MSFT\Program\Code\Android\Pili--"
Set-Location P:\
./scripts/prepare_android.ps1
$env:PUB_CACHE = 'P:\.tools\pub-cache'
```

映射仅供本机开发，源码不变；删除映射前先结束所有构建命令。再次使用其他路径构建时需重新运行准备命令，更新本机生成的包路径。静态分析保留上游弃用/风格提示，以错误和警告阻断构建，不将提示当成功能测试。

## 构建后检查

```sh
python3 -m unittest discover -s scripts/tests -v
python3 scripts/check_android_identity.py --apk build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

Windows 可使用 `python`。完整检查项及多架构参数见 [共存说明](COEXISTENCE.md)。CI 工作流见 [build.yml](../.github/workflows/build.yml)。
