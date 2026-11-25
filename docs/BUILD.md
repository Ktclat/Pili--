# Android 构建指南

[文档索引](README.md) · [安装测试包](INSTALL.md)

## 环境与构建

需要 Git、PowerShell 7、JDK 17、Android SDK 37。上游依赖 Flutter 框架补丁，必须使用项目内隔离环境：

```powershell
git clone https://github.com/Ktclat/Pili--.git
cd Pili--
git clone --depth 1 --branch 3.47.9 https://github.com/flutter/flutter.git .tools/flutter
./scripts/prepare_android.ps1
$env:PUB_CACHE = Join-Path $PWD '.tools/pub-cache'
./.tools/flutter/bin/flutter analyze --no-pub --no-fatal-infos
./.tools/flutter/bin/flutter test --no-pub
./scripts/build_android.ps1
```

输出在 `build/app/outputs/flutter-apk/`。准备脚本校验 SDK 提交、使用独立 Pub 缓存、幂等应用补丁，不重置或删除共享 SDK/缓存。默认强制使用已提交的 `pubspec.lock`；主动修改依赖时使用 `./scripts/prepare_android.ps1 -UpdateLockfile`，审阅并提交锁文件差异。

构建脚本从 `pubspec.yaml` 读取版本名与构建号，统一写入 APK 和关于页，并记录源码提交及构建时间。未提交改动的测试包附加 `-dirty` 标记，正式签名模式要求先提交审阅后的源码。可用 `-TargetPlatform android-arm64` 仅构建 ARM64。应用检查更新时比较安装版本与本仓库的稳定 Release 版本；会忽略预发布，尚无稳定版时会明确提示。

Linux 主机运行回归测试时，`cnativeapi` 的原生钩子还需要 `clang`、`pkg-config`、`libgtk-3-dev`、`libx11-dev`、`libxi-dev`；CI 已安装这些依赖。

正式分发前配置自己的 `android/key.properties` 和签名密钥，密钥不得提交；使用 `./scripts/build_android.ps1 -RequireReleaseSigning` 检查配置后构建，并长期保管同一签名密钥用于后续升级。未配置时使用测试签名；不同机器或 CI 运行生成的测试密钥可能不同，不能依赖这些包互相覆盖升级。CI APK 是测试产物，构建成功不代表成品验收通过。

[v0.5.0-beta.1](https://github.com/Ktclat/Pili--/releases/tag/v0.5.0-beta.1) 使用上述测试签名流程，由 [Actions](https://github.com/Ktclat/Pili--/actions/runs/41020225007) 构建提交 `6bb2ef25ac67233881333adb175603d77b602cb7`。Release 附带对应源码包、`SHA256SUMS.txt` 和 `BUILD_INFO.json`；它不是固定发行密钥签名的稳定版，重新构建也不保证与已发布 APK 字节或签名相同。

当前 [v0.6.0-beta.1](https://github.com/Ktclat/Pili--/releases/tag/v0.6.0-beta.1) 来自 [构建 41070378254](https://github.com/Ktclat/Pili--/actions/runs/41070378254)，精确源码为 `8998b8fc8ee3edc649cebca05422cc78ca3e63b6`；[发布任务](https://github.com/Ktclat/Pili--/actions/runs/41997171383) 复用该次已有 APK，逐包核验后上传并检查远程摘要。本版仍使用测试签名。

## 配置一次发行签名并发布更新

发行人应在自己的电脑上保管并加密备份本项目的专用密钥库及密码。如果已有需要延续的发行密钥，使用原密钥。首次建立签名时可在仓库外运行下面的命令，按提示输入密码并备份生成的文件。

```sh
keytool -genkeypair -storetype PKCS12 -keystore PiliMinus-release.p12 -alias piliminus -keyalg RSA -keysize 3072 -validity 15000
```

在已安装 Python 3、JDK 和 GitHub CLI 的维护者电脑进入本仓库，用有 Actions secrets 和 variables 写权限的账号登录 `gh` 后运行以下配置命令。将路径换成备份过的项目专用密钥库；工具会上传整个文件，使用已有密钥时请填写它的实际别名。

```sh
python3 scripts/configure_android_signing.py --keystore /path/to/PiliMinus-release.p12 --alias piliminus
```

工具在终端隐藏读取密码，设置 `ANDROID_RELEASE_KEYSTORE_BASE64`、`ANDROID_RELEASE_KEY_ALIAS`、`ANDROID_RELEASE_STORE_PASSWORD` 和 `ANDROID_RELEASE_KEY_PASSWORD` 四个仓库 secrets，最后设置公开的证书指纹变量 `ANDROID_RELEASE_CERT_SHA256`。已有指纹时仅能用相同证书重试。

1. 每次发新版先提高 `pubspec.yaml` 的版本名和构建号，写入更新记录。在 `main` 运行 [Android validation build](../.github/workflows/build.yml)。设置密钥前已经完成的运行需要重新构建。
2. 核对 `Sign Android release APKs` 成功及其产物 `Pili--Android-release-signed`。签名任务在独立的 Runner 上复用该次已验证的三包，核对每个 APK 的包名、ABI、版本、源码提交与证书指纹。PR 只运行测试构建。
3. 运行 [Publish Android release](../.github/workflows/release.yml)，填入该次 `run_id` 和版本标签，例如 `v0.6.2`。发布器核验已有包、构建信息与远端附件摘要；稳定更新要求签名连续、版本与构建号递增。公开版本保留其原标签和附件。
4. 用户始终打开同一个稳定下载地址。首次发布稳定版后，常用的 64 位 ARM 安装包也有固定地址。[稳定版](https://github.com/Ktclat/Pili--/releases/latest) · [ARM64 APK](https://github.com/Ktclat/Pili--/releases/latest/download/PiliMinus-arm64-v8a.apk)

预发布使用与源码相符的 `vX.Y.Z-beta.N`、`-alpha.N` 或 `-rc.N` 标签；未启用固定签名时仅可发布测试预览包。应用内检查更新跟随稳定版。

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
