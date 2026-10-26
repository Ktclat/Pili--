# Pili--

基于 [PiliPlus](https://github.com/bggRGjQaUbCoE/PiliPlus) 的哔哩哔哩第三方客户端。当前维护和验证重点是 **Android**，保留上游的视频、弹幕、搜索、动态、直播、收藏和离线缓存实现。不是哔哩哔哩官方客户端。

[English](README.en.md) · [源代码](https://github.com/Ktclat/Pili--) · [问题反馈](https://github.com/Ktclat/Pili--/issues)

## 本项目的改动

- **扫一扫**：首页和“我的”提供入口；支持相机、相册、BV/av 标识。识别后先展示结果；外部网页经确认交给系统浏览器；文本和不安全协议只能复制。切后台时停止相机。
- **会员购**：“我的”中的独立入口。首次点击“下载并启用”才创建 WebView，下载官方 HTML、JavaScript、图片等网页组件；加载成功后记住启用状态。支持失败重试、网页后退、刷新和停用。退出页面释放 WebView，首页不预加载。
- **安全收紧**：移除 TLS 证书验证绕过、私有存储 DocumentsProvider 和向第三方评论检查应用传递登录 Cookie 的联动；账号请求限定到 HTTPS 的 bilibili.com 及其子域；拒绝账号请求跨源重定向，不将 Cookie 复制到重定向目的地。移除关于页隐藏 URL 入口、网络请求原文调试日志和启动错误自动写剪贴板。
- **减少重复工作**：内置网页不再每次打开都清空缓存；失败重试限定 GET/HEAD，避免发评、投币等操作重复提交。
- **独立身份**：名称 Pili--，Android applicationId 为 `io.github.ktclat.piliminus`，反馈与更新地址指向本仓库，可与 PiliPlus 共存。

会员购是官方 H5 应用，**不是独立原生 APK/DEX 插件**。WebView 引擎由系统提供，下载大小和缓存淘汰取决于官方页面及系统。停用关闭自动加载，不清除其他页面共享的登录 Cookie。订单和支付依赖官方页面、账号资格及目标支付应用；未经验证的交易流程不宣称可用，不会自动下单付款。

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
./.tools/flutter/bin/flutter build apk --release --split-per-abi --no-pub --dart-define=pili.name=0.1.0
```

输出在 `build/app/outputs/flutter-apk/`。准备脚本校验 SDK 提交、使用独立 Pub 缓存、幂等应用补丁，不重置或删除共享 SDK/缓存。Git 依赖与 `pubspec.lock` 一起提交。

正式分发前配置自己的 `android/key.properties` 和签名密钥，密钥不得提交。未配置时使用测试签名；CI APK 也是测试产物，构建成功不代表成品验收通过。

## 验证与限制

以安装后的 APK 验收启动、浏览、扫码、权限拒绝、相册识别、不安全链接处理、会员购加载/重试/停用及后台资源释放。实际结果见 [验证记录](docs/VALIDATION.md)。没有截图快照基线或固定帧率门槛；保留的上游回归测试不能替代 APK 验收。

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
