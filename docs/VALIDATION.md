# Android 验证记录

[文档索引](README.md) · [安装说明](INSTALL.md) · [共存说明](COEXISTENCE.md)

验证按源码提交与安装包记录；相同版本号下可能包含多个开发提交，不能把历史结果直接用于当前代码。构建记录见 [Actions](https://github.com/Ktclat/Pili--/actions/workflows/build.yml)。

## 0.4.0+5：移除会员购与小店（2026-10-29）

移除商品浏览、收藏与足迹、分享、专用接口、商城与小店入口及设置，默认导航为首页、动态、我的。旧版商品存储与开关在启动时清理，保留有效导航偏好及其他用户数据。没有加入订单或支付实现。

| 检查 | 本地结果与范围 |
| --- | --- |
| Flutter 全量回归 | **137 项通过**；保留下载、账号、请求边界和音视频质量回归 |
| 导航升级回归 | 旧索引被忽略、自定义排序与隐藏保留、只剩旧入口时恢复默认导航；PageView 和 TabBarView 均实际挂载验证启动、切换、编辑与控制器替换 |
| 旧数据清理 | 使用真实临时 Hive 文件，验证旧商品文件与开关删除、重复启动清理、设置和下载数据保留及关闭重开后的结果 |
| 用户页启动偏好 | 已删除的小店索引回退到默认，保留其他原有索引 |
| 静态分析 | **0 error / 0 warning**；保留 39 条上游 info，使用 `--no-fatal-infos` |
| Python 共存检查器 | **10 项通过**；源码安装身份、备份隔离与快捷方式配置检查通过 |

本轮 APK 构建及实际包身份应核对对应 PR 和 Actions；安装后的升级、扫码与播放体验仍需同版本 APK 在设备上复验。差异格式、Markdown 本地链接与 GitHub 表单 YAML 检查通过。

## 历史构建与回归

以下数目与结果仅适用于当时的提交；已删除模块的测试与预览不再属于当前功能。原始变更和完整旧记录可从对应 PR 与 Git 历史查看。

| 版本 | 当时的记录 |
| --- | --- |
| 0.3.0+4 | [PR #3](https://github.com/Ktclat/Pili--/pull/3)；Flutter 192 项通过，[CI](https://github.com/Ktclat/Pili--/actions/runs/40803393051) 完成三个 ABI 构建及实际包身份检查 |
| 0.2.0+3 | [PR #1](https://github.com/Ktclat/Pili--/pull/1)；整合时 Flutter 173 项通过，[CI](https://github.com/Ktclat/Pili--/actions/runs/40794124475) 完成三个 ABI 构建及实际包身份检查 |
| 0.1.1+2 | Flutter 131 项通过；[CI](https://github.com/Ktclat/Pili--/actions/runs/40453846560)；下载、重试、版本比较与共存改进 |
| 0.1.0+1 | [历史设备记录](validation/0.1.0.md)；初步扫码、视频、相机权限与生命周期证据 |

0.2.0 曾在 Android 11 / API 30 / x86_64 AOSP ATD 模拟器完成双安装：Pili-- UID 10072、PiliPlus UID 10071，私有目录分别为 `/data/user/0/io.github.ktclat.piliminus` 和 `/data/user/0/com.example.piliplus`。该观察不能代替当前版本与 ARM64 真机的验收，也不能用于评估真机性能。

## 复验与未覆盖范围

按照 [构建指南](BUILD.md) 运行分析、测试、构建和 APK 身份检查。设备采证工具与操作示例见 [历史记录](validation/0.1.0.md#如何复验并补充记录)；它只操作安装后的界面，不代替人工验证。双安装操作步骤见 [共存说明](COEXISTENCE.md#真机双安装验收)。

仍待验证：本轮安装后升级、ARM64 真机、登录授权、扫码登录、付费账号、长时间播放/下载、低内存和后台恢复、直播长播、投屏以及其他操作系统。未建立截图比较或帧率门槛。安全审阅边界见 [SECURITY.md](../SECURITY.md)。
