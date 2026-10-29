# Pili--

基于 [PiliPlus](https://github.com/bggRGjQaUbCoE/PiliPlus) 的哔哩哔哩第三方客户端，重点维护 **Android**。提供原生会员购、扫一扫和独立应用身份，可与 PiliPlus 同时安装。

[![Android validation build](https://github.com/Ktclat/Pili--/actions/workflows/build.yml/badge.svg?branch=main)](https://github.com/Ktclat/Pili--/actions/workflows/build.yml)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)

[English](README.en.md) · [安装与下载](docs/INSTALL.md) · [文档](docs/README.md) · [更新记录](CHANGELOG.md) · [问题反馈](https://github.com/Ktclat/Pili--/issues/new/choose)

## 当前状态

当前开发版本为 **0.2.0+3**，尚未发布正式 Release。可从 [GitHub Actions](https://github.com/Ktclat/Pili--/actions/workflows/build.yml) 获取成功构建的测试 APK；安装和升级前请阅读 [签名说明](docs/INSTALL.md)。构建成功不等于所有真机与业务场景已验收，具体结果按提交记录在 [验证记录](docs/VALIDATION.md)。

本项目不是哔哩哔哩官方客户端。其他平台源码保留，目前仅对 Android 提供构建与验证说明。

## 主要功能

| 功能 | 当前实现 |
| --- | --- |
| 视频与社区 | 保留上游的视频、弹幕、搜索、动态、直播、收藏和离线缓存实现 |
| 原生会员购 | Flutter 推荐流、分类、搜索、商品详情、图集缩放、保序图文与详情内继续搜索 |
| 可调整的导航 | 默认显示首页、动态、会员购、我的；支持隐藏会员购和调整顺序，立即生效 |
| 扫一扫 | 相机、相册、BV/av 识别；先展示结果，外部网页经确认后打开；后台释放相机 |
| 与 PiliPlus 共存 | 独立包名、私有数据与默认下载目录；桌面快捷方式绑定本应用 |
| 下载与网络改进 | 修复断点续传、完成竞态；保留 TLS 校验，限制账号请求目的地、重定向和写请求重试 |

会员购随 APK 内置，无需额外下载或启用。在 **设置 → 外观设置 → 在导航栏显示会员购** 中可关闭或恢复；隐藏后仍可从“我的 → 会员购”进入。

商品浏览使用官方公开接口，不附带账号 Cookie。价格区分商品价、预售定金和活动提示；**购买、选规格、订单与支付由官方页面完成**。接口可能变化，最终价格与库存以官方结算为准。实现及 REA/官方客户端参考范围见 [原生会员购说明](docs/NATIVE_MALL.md)。

## 安装与共存

1. 在 [Actions](https://github.com/Ktclat/Pili--/actions/workflows/build.yml) 中选择目标分支和提交对应的成功构建。
2. 下载 `Pili--Android-test-signed` 附件，解压后选择设备对应的 APK；多数当前 Android 手机使用 `arm64-v8a`。
3. 保留已安装的 PiliPlus，安装 Pili--。两者安装 ID 分别为 `com.example.piliplus` 与 `io.github.ktclat.piliminus`。

附件需登录 GitHub 下载，默认保留 14 天。不同 CI 构建的测试签名可能不同，不能保证覆盖升级；遇到签名冲突先核对来源并保留应用数据。详见 [安装说明](docs/INSTALL.md) 和 [共存说明](docs/COEXISTENCE.md)。

## 开发与反馈

项目使用隔离的 **Flutter 3.47.8、JDK 17、Android SDK 37、PowerShell 7** 和已提交的锁文件。上游 Flutter 补丁需要按 [构建指南](docs/BUILD.md) 准备，不能直接使用共享 SDK 构建。

- [贡献指南](CONTRIBUTING.md)：开发流程、测试范围和提交方式。
- [验证记录](docs/VALIDATION.md)：自动测试、实际设备结果和未验收项目。
- [后续计划](docs/ROADMAP.md)：真机验证、签名发行与待完善事项。
- [反馈问题或建议](https://github.com/Ktclat/Pili--/issues/new/choose)：附版本/提交、设备和复现步骤。
- [安全说明与报告方式](SECURITY.md)：安全问题请勿附带公开账号凭据。

## 许可证与来源

保留上游 [GPL v3 许可证](LICENSE)、版权声明和 Git 历史。来源及修改说明见 [NOTICE](NOTICE)；分发修改版及二进制时，应按许可证提供对应源码和构建材料，依赖保留各自许可证。

感谢 [PiliPlus](https://github.com/bggRGjQaUbCoE/PiliPlus)、[PiliPala](https://github.com/guozhigq/pilipala)、[PiliPalaX](https://github.com/orz12/PiliPalaX)、[bilibili-API-collect](https://github.com/SocialSisterYi/bilibili-API-collect)、[media-kit](https://github.com/media-kit/media-kit) 及依赖贡献者。沿用图标来自上游，不代表官方授权或背书。本项目不提供付费内容破解，不绕过会员权限。
