# Pili--

基于 [PiliPlus](https://github.com/bggRGjQaUbCoE/PiliPlus) 继续开发、独立维护的哔哩哔哩第三方客户端，重点维护 **Android**。保留视频与社区功能，提供扫一扫和独立应用身份，可与 PiliPlus 同时安装。

[Ktclat](https://github.com/Ktclat) 独立负责本项目的开发、发布和用户支持，与 PiliPlus、PiliPala 和 PiliPalaX 维护团队无隶属关系。上游代码的许可、版权和署名见 [NOTICE](NOTICE) 与 [来源说明](docs/ACKNOWLEDGEMENTS.md)。

[![Android validation build](https://github.com/Ktclat/Pili--/actions/workflows/build.yml/badge.svg?branch=main)](https://github.com/Ktclat/Pili--/actions/workflows/build.yml)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)

[English](README.en.md) · [常见问题](docs/FAQ.md) · [安装与下载](docs/INSTALL.md) · [文档](docs/README.md) · [更新记录](CHANGELOG.md) · [问题反馈](https://github.com/Ktclat/Pili--/issues/new/choose)

## 当前状态

主分支 **0.6.3+13** 更新了首页和「我的」工具栏，并包含 PiliPlus 2.2.1 的播放、评论、投屏和离线缓存修复。最新发行版 **0.6.0+7** 为 Android 预发布测试包，包含悬浮导航更新。[预发布下载](https://github.com/Ktclat/Pili--/releases/tag/v0.6.0-beta.1) · [安装与签名](docs/INSTALL.md)

0.6.3+13 已通过 448 项 Flutter 测试、31 项项目脚本测试和三个 Android 架构的安装包检查。已在 Android 11 模拟器上验证窄屏搜索、工具换行和扫码页的识别链接入口。[0.6.3+13 测试 APK](https://github.com/Ktclat/Pili--/actions/runs/45600396159/artifacts/15015587940) · [构建记录](https://github.com/Ktclat/Pili--/actions/runs/45600396159) · [设备截图与结果](docs/VALIDATION.md)

## 主要功能

| 功能 | 当前实现 |
| --- | --- |
| 视频与社区 | 保留上游的视频、弹幕、搜索、动态、直播、收藏和离线缓存实现 |
| 动态页 UP 主 | 分类下方横向显示直播与关注的 UP 主，可滑动和筛选。升级后默认使用顶部布局 |
| 可调整的导航 | 默认显示首页、动态、我的；支持隐藏和调整顺序，立即生效 |
| 右上角按钮 | 在「设置 → 外观设置 → 右上角按钮」分别勾选、排序首页和「我的」的工具。取消勾选即隐藏，首页搜索框随剩余空间伸缩 |
| 悬浮胶囊底栏 | 0.6.0 默认启用；拖动选中背景，停稳后切页，外观开关即时生效；保留已保存的关闭偏好 |
| 扫码与登录授权 | 首页和「我的」默认显示「扫一扫」。可用相机或相册识别二维码，也可为本人设备上的网页或 TV 登录请求确认授权 |
| 同机登录（0.6.1 开发版） | 兼容的 Android App 可跳到 Pili-- 确认登录，也可手动粘贴官方扫码登录链接。[接入说明](docs/INPUT_RECOGNITION.md) |
| 分享与链接识别 | 点「扫一扫」右上角的链接图标可识别分享文案中的 B 站链接、b23.tv 与 BV/av 号，也可通过 Android 分享面板发送到 Pili-- |
| 剪贴板选项 | 自动识别默认关闭，可在隐私设置开启；另有手动粘贴识别入口 |
| 与 PiliPlus 共存 | 独立包名、私有数据与默认下载目录；桌面快捷方式绑定本应用 |
| 下载与网络改进 | 修复断点续传、完成竞态；保留 TLS 校验，限制账号请求目的地、重定向和写请求重试 |

从 0.4.0 起移除会员购和 UP 主页小店，项目聚焦视频、社区、扫码、下载稳定性与共存。升级会清理旧商品收藏、浏览足迹和相关开关；视频收藏、播放历史、账号和下载记录不受这项清理影响。

悬浮底栏支持普通点击；拖动时选中背景连续跟手，停稳约 200 毫秒才切换页面，快速划过或提前松手会取消本次待切换。入口与交互约定见 [悬浮导航说明](docs/FLOATING_NAVIGATION.md)，本轮验证进度见 [验证记录](docs/VALIDATION.md)。

本次采用新的源码快照历史；旧历史与许可来源见 [仓库重建说明](docs/REPOSITORY_RESTART.md)。

## 安装与共存

1. 打开 [v0.6.0-beta.1 Release](https://github.com/Ktclat/Pili--/releases/tag/v0.6.0-beta.1)，按设备架构下载 `test-signed.apk`；多数当前 Android 手机使用 `arm64-v8a`。
2. 使用同页的 `SHA256SUMS.txt` 核对下载内容；源码包和 `BUILD_INFO.json` 记录该包的源码及构建来源。
3. 保留已安装的 PiliPlus，安装 Pili--。两者安装 ID 分别为 `com.example.piliplus` 与 `io.github.ktclat.piliminus`。

从 0.6.3+11 起，Android 用户在应用内点「下载更新」时，应用会核对正式版发布记录中的包名、签名指纹、架构和构建号。签名不同时可先在「设置 → 关于」导出数据，再决定是否迁移。首次正式发布后，各版本共用同一个下载入口。[稳定版](https://github.com/Ktclat/Pili--/releases/latest) · [签名与迁移](docs/INSTALL.md#旧测试签名迁移)

预发布版需手动下载，不同 CI 构建的测试签名可能不同。下载开发测试包需登录 GitHub，Actions 附件默认保留 14 天。[Actions 构建](https://github.com/Ktclat/Pili--/actions/workflows/build.yml) · [安装说明](docs/INSTALL.md) · [共存说明](docs/COEXISTENCE.md)

## 开发与反馈

项目使用隔离的 **Flutter 3.47.9、JDK 17、Android SDK 37、PowerShell 7** 和已提交的锁文件。上游 Flutter 补丁需要按 [构建指南](docs/BUILD.md) 准备，不能直接使用共享 SDK 构建。

- [贡献指南](CONTRIBUTING.md)：开发流程、测试范围和提交方式。
- [验证记录](docs/VALIDATION.md)：自动测试、实际设备结果和未验收项目。
- [后续计划](docs/ROADMAP.md)：真机验证、签名发行与待完善事项。
- [反馈问题或建议](https://github.com/Ktclat/Pili--/issues/new/choose)：附版本/提交、设备和复现步骤。
- [安全说明与报告方式](SECURITY.md)：安全问题请勿附带公开账号凭据。

## 许可证与来源

本项目保留上游 GPL v3 许可证、版权声明和来源署名。分发修改版及二进制时，应按许可证提供对应源码和构建材料。依赖保留各自的许可证。[许可证](LICENSE) · [来源与修改说明](NOTICE)

感谢 [PiliPlus](https://github.com/bggRGjQaUbCoE/PiliPlus)、[PiliPala](https://github.com/guozhigq/pilipala)、[PiliPalaX](https://github.com/orz12/PiliPalaX)、[bilibili-API-collect](https://github.com/SocialSisterYi/bilibili-API-collect)、[media-kit](https://github.com/media-kit/media-kit) 及依赖贡献者。完整的上游、依赖与素材来源见 [来源与致谢](docs/ACKNOWLEDGEMENTS.md)。
