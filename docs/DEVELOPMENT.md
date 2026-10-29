# 开发导览

[项目首页](../README.md) · [构建指南](BUILD.md) · [贡献指南](../CONTRIBUTING.md) · [来源与致谢](ACKNOWLEDGEMENTS.md)

Pili-- 基于 PiliPlus 独立维护，当前重点是 Android。环境准备、锁文件、补丁、构建命令与签名操作集中在 [Android 构建指南](BUILD.md)，避免多份命令随版本漂移；测试与设备结果按提交记录在 [验证记录](VALIDATION.md)。

## 环境要点

| 工具 | 当前要求 |
| --- | --- |
| Flutter | 项目内 `.tools/flutter`，版本 **3.47.8**；准备脚本核对提交 `737ba8f885dc774b53b442759999a312c9461e4e` |
| Dart | 使用该 Flutter 自带的 Dart；依赖约束见 [pubspec.yaml](../pubspec.yaml) |
| PowerShell | **7**；Linux 可运行 `pwsh`，不要把脚本设置的环境变量当作已回传给外层 Bash |
| Java / Android | **JDK 17、SDK 37**；Gradle 使用仓库 Wrapper，NDK 随固定 Flutter 配置 |
| Linux 主机库 | `clang`、`pkg-config`、`libgtk-3-dev`、`libx11-dev`、`libxi-dev`，用于原生回归测试 |

上游 Flutter 与 `material_ui` 补丁需要隔离环境；不得把准备脚本应用到共享 SDK。默认强制已提交的锁文件，只有主动升级依赖时才使用 `-UpdateLockfile` 并审阅差异。

## 源码与工具入口

| 路径 | 用途 |
| --- | --- |
| [lib/pages/](../lib/pages/) | 视频、动态、扫码及设置等页面交互 |
| [lib/http/](../lib/http/) | API、网络请求、重定向与重试 |
| [账号模块](../lib/utils/accounts/account_manager/README.md) | 请求身份、Cookie 与迟到回调边界 |
| [lib/utils/storage.dart](../lib/utils/storage.dart) | 本地数据生命周期与旧功能数据清理 |
| [Android 工程](../android/) | 宿主、Manifest、资源和包身份配置 |
| [构建脚本](../scripts/build_android.ps1) | 统一版本、提交、时间和签名检查 |
| [tool/](../tool/README.md) | JNI 生成工具，普通 APK 构建通常不需重新生成 |
| [test/](../test/) | 自动回归；[历史证据](validation/)按版本保存 |

其他平台源码保留，目录存在不表示已经完成适配或验收。iOS 资源说明见 [启动资源](../ios/Runner/Assets.xcassets/LaunchImage.imageset/README.md)。

## 修改与同步上游

从 `main` 创建用途明确的分支。按改动运行相关回归，补充能够复现实际风险的测试；CI 会执行分析、全量回归、三个 ABI 构建和最终 APK 身份检查。纯文档修改检查内容、链接和命令即可。

Android 安装 ID `io.github.ktclat.piliminus` 与 Java/JNI namespace、Dart 包名用途不同。内部仍保留 `com.example.piliplus` 与 `PiliPlus`，不能批量替换；隔离实现见 [共存说明](COEXISTENCE.md)。

同步上游时核对源仓库和提交，保留署名及许可；选择提交可用 `git cherry-pick -x` 记录来源。合并后复核框架补丁、锁文件、账号请求策略、安装身份和本项目功能，再运行对应验证。来源与第三方许可见 [致谢](ACKNOWLEDGEMENTS.md) 和 [NOTICE](../NOTICE)。
