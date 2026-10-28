# Pili--

基于 [PiliPlus](https://github.com/bggRGjQaUbCoE/PiliPlus) 的哔哩哔哩第三方客户端。当前维护和验证重点是 **Android**，保留上游的视频、弹幕、搜索、动态、直播、收藏和离线缓存实现。不是哔哩哔哩官方客户端。

[English](README.en.md) · [源代码](https://github.com/Ktclat/Pili--) · [问题反馈](https://github.com/Ktclat/Pili--/issues)

## 本项目的改动

- **扫一扫**：首页和“我的”提供入口；支持相机、相册、BV/av 标识。识别后先展示结果；外部网页经确认交给系统浏览器；文本和不安全协议只能复制。切后台时停止相机。
- **原生会员购**：随应用内置，默认出现在导航栏，也可从“我的”进入。商品推荐、新品分类、搜索和商品详情由 Flutter 原生组件展示，直接读取官方公开接口，不再下载或启用网页组件。在“设置 → 外观设置 → 在导航栏显示会员购”中可隐藏或恢复导航入口；导航栏编辑也可调整位置。
- **安全收紧**：移除 TLS 证书验证绕过、私有存储 DocumentsProvider 和向第三方评论检查应用传递登录 Cookie 的联动；账号请求限定到 HTTPS 的 bilibili.com 及其子域；拒绝账号请求跨源重定向，不将 Cookie 复制到重定向目的地。移除关于页隐藏 URL 入口、网络请求原文调试日志和启动错误自动写剪贴板。
- **减少重复工作**：内置网页不再每次打开都清空缓存；失败重试限定 GET/HEAD，避免发评、投币等操作重复提交。
- **独立身份**：名称 Pili--，Android applicationId 为 `io.github.ktclat.piliminus`，反馈与更新地址指向本仓库。桌面快捷方式明确绑定当前应用，账号、设置和默认下载目录由 Android 包名隔离，可与 PiliPlus 共存。检查方法与双安装验收步骤见 [共存说明](docs/COEXISTENCE.md)。
- **下载续传**：校验续传响应范围和实际长度；服务器返回完整文件时重新写入，避免将完整文件追加到旧片段后误报成功。

会员购浏览页面是随 APK 发布的原生实现，不是远程下载的 APK/DEX 插件。列表保留官方返回的定金、优惠价与“起”等标识；详情按详情接口展示商品价格，实际成交条件以官方结算页为准。购买入口交给官方平台完成登录、选购和支付，本客户端不提交购物订单或付款。公开接口及实现范围见 [原生会员购说明](docs/NATIVE_MALL.md)。

## 构建 Android

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

## 验证与限制

主分支和 PR 的 CI 均执行静态分析、回归测试、分 ABI 构建及 APK 包名/Provider/快捷方式检查。回归覆盖下载续传、URL 信任边界、重定向与重试、会员购导航及更新版本选择。

以安装后的 APK 验收启动、浏览、扫码、权限拒绝、相册识别、不安全链接处理、会员购推荐/分类/搜索/详情、失败重试及导航显示开关。历史模拟器操作见 [验证记录](docs/VALIDATION.md)，应按记录中的版本判断覆盖范围。没有截图快照基线或固定帧率门槛；自动测试不能替代 APK 和双安装真机验收。

其他平台源码保留，但不承诺已验证。模拟器不能替代真机对焦、长时间播放、低内存设备或真实支付测试。安全审查范围见 [安全说明](SECURITY.md)，不据此保证整个依赖链“绝无后门”。

## 许可证与来源

保留上游 [GPL v3 许可证](LICENSE)、文件版权声明和 Git 历史。来源及修改说明见 [NOTICE](NOTICE)。分发修改版和二进制时应按许可证提供对应源码及构建材料；依赖保留各自许可证。应用内可查看开源许可。

不提供付费内容破解，不绕过会员权限。感谢 [PiliPlus](https://github.com/bggRGjQaUbCoE/PiliPlus)、[PiliPala](https://github.com/guozhigq/pilipala)、[PiliPalaX](https://github.com/orz12/PiliPalaX)、[bilibili-API-collect](https://github.com/SocialSisterYi/bilibili-API-collect)、[media-kit](https://github.com/media-kit/media-kit) 及依赖贡献者。沿用图标来自上游，不代表官方授权或背书。

### Windows 含空格路径

Dart 原生构建钩子在带空格的 SDK 路径下可能启动失败。可将项目映射到一个**尚未占用**的盘符，再从该盘符运行上述准备和构建命令，例如：

```powershell
subst P: "D:\OneDrive - MSFT\Program\Code\Android\Pili--"
Set-Location P:\
./scripts/prepare_android.ps1
$env:PUB_CACHE = 'P:\.tools\pub-cache'
```

映射仅供本机开发，源码不变；删除映射前先结束所有构建命令。再次使用其他路径构建时需重新运行准备命令，更新本机生成的包路径。静态分析保留上游弃用/风格提示，以错误和警告阻断构建，不将提示当成功能测试。
