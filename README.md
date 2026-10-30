# Pili--

基于 [PiliPlus](https://github.com/bggRGjQaUbCoE/PiliPlus) 继续开发、独立维护的哔哩哔哩第三方客户端，重点维护 **Android**。保留视频与社区功能，提供扫一扫和独立应用身份，可与 PiliPlus 同时安装。

本项目由 [Ktclat](https://github.com/Ktclat) 独立维护，开发、发布和用户支持均由本仓库负责。Pili-- 不是 PiliPlus、PiliPala 或 PiliPalaX 团队发行的版本，与这些上游维护团队无隶属、合作或背书关系；代码来源、许可和版权仍按 [NOTICE](NOTICE) 与 [来源说明](docs/ACKNOWLEDGEMENTS.md) 保留。

[![Android validation build](https://github.com/Ktclat/Pili--/actions/workflows/build.yml/badge.svg?branch=main)](https://github.com/Ktclat/Pili--/actions/workflows/build.yml)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)

[English](README.en.md) · [常见问题](docs/FAQ.md) · [安装与下载](docs/INSTALL.md) · [文档](docs/README.md) · [更新记录](CHANGELOG.md) · [问题反馈](https://github.com/Ktclat/Pili--/issues/new/choose)

## 当前状态

当前版本为 **0.5.0+6**，已提供 [v0.5.0-beta.1 预发布下载](https://github.com/Ktclat/Pili--/releases/tag/v0.5.0-beta.1)，尚无稳定发行版。本次使用 Actions 测试签名；安装和升级前请阅读 [签名说明](docs/INSTALL.md)。构建成功不等于所有真机与业务场景已验收，具体结果按提交记录在 [验证记录](docs/VALIDATION.md)。

本项目不是哔哩哔哩官方客户端。其他平台源码保留，目前仅对 Android 提供构建与验证说明。

0.5.0 源码快照已通过 [三架构构建与回归](https://github.com/Ktclat/Pili--/actions/runs/40985731174)：278 项 Flutter 测试、10 项 Python 检查通过。模拟器上的分享接收、识别与隐私开关已验证，截图见 [设备记录](docs/validation/0.5.0.md)；真实账号扫码授权与 ARM64 真机仍待验收。

## 主要功能

| 功能 | 当前实现 |
| --- | --- |
| 视频与社区 | 保留上游的视频、弹幕、搜索、动态、直播、收藏和离线缓存实现 |
| 可调整的导航 | 默认显示首页、动态、我的；支持隐藏和调整顺序，立即生效 |
| 扫码与登录授权 | 相机/相册识别；网页与 TV 登录码进入原生确认页，核对账号及登录位置后才授权 |
| 分享与链接识别 | 接收 Android 文本分享，支持文案中的 B 站链接、b23.tv 与 BV/av；确认后打开 |
| 剪贴板选项 | 自动识别默认关闭，可在隐私设置开启；另有手动粘贴识别入口 |
| 与 PiliPlus 共存 | 独立包名、私有数据与默认下载目录；桌面快捷方式绑定本应用 |
| 下载与网络改进 | 修复断点续传、完成竞态；保留 TLS 校验，限制账号请求目的地、重定向和写请求重试 |

从 0.4.0 起移除会员购和 UP 主页小店，项目聚焦视频、社区、扫码、下载稳定性与共存。升级会清理旧商品收藏、浏览足迹和相关开关；视频收藏、播放历史、账号和下载记录不受这项清理影响。

扫码授权使用当前登录账号，仅用于你本人设备的登录。遇到额外安全验证时交由官方处理；不自动授权、不持久保存登录码。自动剪贴板识别仅在开启后进入前台时读取，分享与剪贴板内容不上传到项目服务器。使用入口和开关见 [安装与使用说明](docs/INSTALL.md)。

本次采用新的源码快照历史；旧历史与许可来源见 [仓库重建说明](docs/REPOSITORY_RESTART.md)。

## 安装与共存

1. 打开 [v0.5.0-beta.1 Release](https://github.com/Ktclat/Pili--/releases/tag/v0.5.0-beta.1)，按设备架构下载 `test-signed.apk`；多数当前 Android 手机使用 `arm64-v8a`。
2. 使用同页的 `SHA256SUMS.txt` 核对下载内容；源码包和 `BUILD_INFO.json` 记录该包的源码及构建来源。
3. 保留已安装的 PiliPlus，安装 Pili--。两者安装 ID 分别为 `com.example.piliplus` 与 `io.github.ktclat.piliminus`。

预发布版不会触发应用内稳定更新提示，请手动下载。不同 CI 构建的测试签名可能不同，不能保证覆盖升级；遇到签名冲突先核对来源并保留应用数据。开发测试包仍可从 [Actions](https://github.com/Ktclat/Pili--/actions/workflows/build.yml) 获取，其附件需登录下载、默认保留 14 天。详见 [安装说明](docs/INSTALL.md) 和 [共存说明](docs/COEXISTENCE.md)。

## 开发与反馈

项目使用隔离的 **Flutter 3.47.8、JDK 17、Android SDK 37、PowerShell 7** 和已提交的锁文件。上游 Flutter 补丁需要按 [构建指南](docs/BUILD.md) 准备，不能直接使用共享 SDK 构建。

- [贡献指南](CONTRIBUTING.md)：开发流程、测试范围和提交方式。
- [验证记录](docs/VALIDATION.md)：自动测试、实际设备结果和未验收项目。
- [后续计划](docs/ROADMAP.md)：真机验证、签名发行与待完善事项。
- [反馈问题或建议](https://github.com/Ktclat/Pili--/issues/new/choose)：附版本/提交、设备和复现步骤。
- [安全说明与报告方式](SECURITY.md)：安全问题请勿附带公开账号凭据。

## 许可证与来源

保留上游 [GPL v3 许可证](LICENSE)、版权声明及必要来源署名。来源及修改说明见 [NOTICE](NOTICE)；分发修改版及二进制时，应按许可证提供对应源码和构建材料，依赖保留各自许可证。仓库历史或贡献统计的整理不改变这些来源与许可义务。

感谢 [PiliPlus](https://github.com/bggRGjQaUbCoE/PiliPlus)、[PiliPala](https://github.com/guozhigq/pilipala)、[PiliPalaX](https://github.com/orz12/PiliPalaX)、[bilibili-API-collect](https://github.com/SocialSisterYi/bilibili-API-collect)、[media-kit](https://github.com/media-kit/media-kit) 及依赖贡献者。完整的上游、依赖与素材来源见 [来源与致谢](docs/ACKNOWLEDGEMENTS.md)。沿用图标来自上游，不代表官方授权或背书。本项目不提供付费内容破解，不绕过会员权限。
