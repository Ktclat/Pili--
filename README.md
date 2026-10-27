<div align="center">

<img src="assets/images/logo/logo_2.png" width="96" height="96" alt="Pili-- 沿用的上游项目图标">

# Pili--

**从熟悉的体验出发，做一点自己想用的功能。**

基于 PiliPlus 的哔哩哔哩第三方客户端 · 个人兴趣 Fork · Android 优先

[![Platform](https://img.shields.io/badge/platform-Android-3DDC84?logo=android&logoColor=white)](docs/DEVELOPMENT.md)
[![Flutter](https://img.shields.io/badge/Flutter-3.47.8-02569B?logo=flutter&logoColor=white)](docs/DEVELOPMENT.md)
[![License](https://img.shields.io/badge/license-GPL_v3-blue)](LICENSE)

[English](README.en.md) · [获取与构建](#获取与构建) · [文档导航](#文档导航) · [问题反馈](https://github.com/Ktclat/Pili--/issues) · [致谢](docs/ACKNOWLEDGEMENTS.md)

</div>

## 关于项目

**Pili-- 是基于 [PiliPlus](https://github.com/bggRGjQaUbCoE/PiliPlus) 独立维护的个人兴趣衍生项目（fork）**，主要用于学习、自用和尝试新功能。由 [Ktclat](https://github.com/Ktclat) 维护，当前把开发与验证精力放在 Android 上，按个人时间持续改进。

视频播放、弹幕、搜索、动态、直播、收藏、离线缓存等基础能力，来自上游及其社区的长期积累。Pili-- 在这份基础上加入自己的功能和调整，使用独立的项目名称、Android 应用 ID、反馈入口与更新来源。

> 本项目不是哔哩哔哩官方客户端，也不代表 PiliPlus、PiliPalaX 或 PiliPala 的官方版本。感谢上游作者与每一位贡献者；项目来源、版权声明和许可证均予以保留。

## 有什么不一样

| 方向 | 当前实现 |
| --- | --- |
| 熟悉的浏览体验 | 延续上游的视频、弹幕、搜索、动态、直播、收藏与离线缓存实现；可用性仍受平台接口和账号权限影响。 |
| 扫一扫 | 首页和“我的”提供入口，支持相机与相册二维码识别，以及二维码中的 BV / av 标识；先展示结果，再由用户选择打开或复制。 |
| 按需会员购 | 在“我的”中主动启用后加载官方会员购网页，支持加载失败重试、工具栏网页后退、刷新和停用。首页不预加载，离开页面后释放 WebView。 |
| 账号与网络边界 | 收紧携带账号信息的请求目标和重定向策略，移除证书验证绕过、私有目录导出入口及向第三方应用传递登录 Cookie 的联动。详见[安全说明](SECURITY.md)。 |
| 资源使用 | 扫码切到后台时停止相机；内置网页复用缓存；自动重试限于 GET / HEAD 请求，减少写操作重复提交的风险。 |
| 独立维护 | Android 应用 ID 为 `io.github.ktclat.piliminus`，源码、问题反馈与更新检查均指向本仓库。 |

这里描述的是当前仓库已有实现，不是完整功能验收清单。具体测试环境、通过项和未验证项见[验证记录](docs/VALIDATION.md)；规划中或尚未合并的功能不计入已实现能力。

## 界面一览

以下是仓库保留的 **2026-10-27 Android 模拟器验收截图**，展示扫码和会员购流程，具体操作环境与结果见[历史验收记录](docs/VALIDATION.md)。

| 扫码结果确认 | 按需加载会员购 | 断网与重试提示 |
| :---: | :---: | :---: |
| <img src="docs/validation/camera-qr.png" width="240" alt="相机识别二维码后的结果确认窗口"> | <img src="docs/validation/mall.png" width="240" alt="启用后加载的官方会员购网页"> | <img src="docs/validation/mall-offline.png" width="240" alt="会员购断网后的失败与重试提示"> |

沿用图标的来源见[致谢与来源](docs/ACKNOWLEDGEMENTS.md)。

## 获取与构建

### 获取安装包

- **发布版本**：以[本仓库 Releases](https://github.com/Ktclat/Pili--/releases) 中实际发布的附件和说明为准。没有发布包时，请自行构建。
- **开发测试包**：若 [Actions](https://github.com/Ktclat/Pili--/actions/workflows/build.yml) 的成功运行提供构建附件，可按对应提交试用。当前工作流的 APK 使用测试签名，附件会过期，不能视为正式发行版。
- **自行构建**：完整环境、签名和排错步骤见[开发与构建指南](docs/DEVELOPMENT.md)。

独立应用 ID 用于区分安装和应用数据，不会自动迁移上游客户端的登录信息、设置或缓存。双安装时的链接接管、桌面快捷方式等行为，请以对应版本的验证结果为准。

### Android 快速构建

准备 Git、**PowerShell 7**、JDK 17 和 Android SDK 37。以下命令在 PowerShell 中执行；Linux 主机依赖、Android SDK 配置和 Windows 路径问题请先看[开发指南](docs/DEVELOPMENT.md)。

```powershell
git clone https://github.com/Ktclat/Pili--.git
cd Pili--
git clone --depth 1 --branch 3.47.8 https://github.com/flutter/flutter.git .tools/flutter
./scripts/prepare_android.ps1
$env:PUB_CACHE = Join-Path $PWD '.tools/pub-cache'
$version = [regex]::Match((Get-Content pubspec.yaml -Raw), '(?m)^version:\s*([0-9.]+)\+([0-9]+)\s*$')
if (-not $version.Success) { throw 'Check the version in pubspec.yaml.' }
./.tools/flutter/bin/flutter build apk --release --split-per-abi --no-pub `
  "--dart-define=pili.name=$($version.Groups[1].Value)" `
  "--dart-define=pili.code=$($version.Groups[2].Value)"
```

APK 输出至 `build/app/outputs/flutter-apk/`。项目依赖上游 Flutter 框架补丁，请使用 `.tools/flutter` 隔离 SDK 和配套准备脚本。命令从 `pubspec.yaml` 读取版本并同步到关于页；提交号、构建时间等完整元数据的写入方式见[开发指南](docs/DEVELOPMENT.md)。

未配置自己的签名密钥时，release 模式构建也会使用测试签名。正式分发前需要配置签名、核对对应源码，并执行安装后的验收。

## 使用前了解

- **当前主要验证 Android**。仓库保留其他平台源码，不代表这些平台已经完成适配、验收或发布。
- **会员购是官方 H5 页面**。首次启用下载 HTML、JavaScript、图片等网页资源，使用系统 WebView；不是另行安装的 APK / DEX 插件。订单、登录与支付依赖官方页面和目标应用，真实交易流程尚未完成验收。
- **扫码结果不会自动执行**。文本和不支持的协议只提供复制；外部网页经用户确认后交给系统浏览器。扫码登录授权请使用官方 App。
- **第三方客户端仍然需要联网**。视频和账号业务依赖哔哩哔哩服务，更新检查使用 GitHub；可选第三方服务和数据边界见[安全说明](SECURITY.md)。
- **不提供付费内容破解或会员权限绕过**。内容访问能力取决于官方服务、账号资格及适用规则。

## 文档导航

| 文档 | 内容 |
| --- | --- |
| [常见问题](docs/FAQ.md) | 与上游的关系、历史贡献者、安装共存、会员购、扫码及版本识别 |
| [开发与构建](docs/DEVELOPMENT.md) | 环境准备、分析与测试、Android 构建、签名、目录结构及排错 |
| [参与贡献](CONTRIBUTING.md) | 如何报告问题、提出功能、提交改动和同步上游 |
| [验证记录](docs/VALIDATION.md) | 已执行的历史验收、截图、APK 哈希与未覆盖范围 |
| [安全说明](SECURITY.md) | 已收紧的边界、网络与数据行为、漏洞反馈方式 |
| [致谢与来源](docs/ACKNOWLEDGEMENTS.md) | 上游项目、历史贡献、依赖与素材来源 |
| [来源声明](NOTICE) / [许可证](LICENSE) | 衍生关系、修改说明与许可文本 |

## 反馈与参与

欢迎分享实际使用中的问题和你想尝试的功能。请先查阅[常见问题](docs/FAQ.md)，再到 **[Pili-- Issues](https://github.com/Ktclat/Pili--/issues)** 反馈，附上版本或提交号、设备环境和复现步骤。Pili-- 特有的问题由本仓库跟踪，避免把维护压力转给上游。

准备贡献代码或文档时，请阅读[贡献指南](CONTRIBUTING.md)。这是个人兴趣项目，功能取舍和维护节奏会随时间调整，不承诺固定发布周期。

## 致谢与许可

首先感谢 **[PiliPlus](https://github.com/bggRGjQaUbCoE/PiliPlus)** 提供直接的代码基础，也向 **[PiliPala](https://github.com/guozhigq/pilipala)**、**[PiliPalaX](https://github.com/orz12/PiliPalaX)** 及历代贡献者致敬。感谢 [bilibili-API-collect](https://github.com/SocialSisterYi/bilibili-API-collect)、[Flutter](https://github.com/flutter/flutter)、[media-kit](https://github.com/media-kit/media-kit) 和其他开源依赖，让这些尝试成为可能。完整说明见[致谢与来源](docs/ACKNOWLEDGEMENTS.md)。

项目沿用上游 [GPL v3 许可证](LICENSE)，文件级许可与第三方组件的独立声明继续适用。修改和再分发请遵守相应许可证，并按要求提供对应源码与构建材料；“个人兴趣、自用”描述的是项目定位，不是额外的许可限制。详见 [NOTICE](NOTICE)。
