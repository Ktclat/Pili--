# Android 验证记录

[文档索引](README.md) · [安装说明](INSTALL.md) · [共存说明](COEXISTENCE.md)

同一版本号可能包含多个开发提交。下文分别标记本次整合、此前 APK 与历史版本的范围；实际构建结果应核对 [Actions](https://github.com/Ktclat/Pili--/actions/workflows/build.yml) 的源码提交，不能将早期成功套用到新代码。

## 0.2.0+3：详情改进与文档整合（2026-10-29）

本次整合基于 `9b90897`，修正详情文本重复渲染、分析警告及详情内搜索测试的滚动位置。最终提交与 CI 链接见 [PR #1](https://github.com/Ktclat/Pili--/pull/1)。

| 检查 | 本地结果与范围 |
| --- | --- |
| Flutter 全量回归 | **173 项通过**；包含详情图文顺序、预售信息、应用内继续搜索、详情失败重试与原有业务回归 |
| 静态分析 | **0 error / 0 warning**；保留 39 条上游 info，使用 `--no-fatal-infos` |
| Python 共存检查器 | **10 项通过**；源码应用身份检查通过 |
| 差异及文档 | 检查差异格式、Markdown 本地链接与反馈表单 YAML |

云端工作流还会执行三个 ABI 的 APK 构建，以及实际包名、Provider 和快捷方式检查。是否通过以该提交的 CI 结果为准。新增详情交互尚未完成安装后联网设备验收。

## 0.2.0+3：基础原生会员购（2026-10-28）

以下已执行结果对应提交 [`f4ceb2f`](https://github.com/Ktclat/Pili--/commit/f4ceb2f6347ab02e43606f0b3634dce277d7af17)，与上文新增详情改进区分：

- Flutter **170 项通过**；静态分析无 error/warning；Python **10 项通过**。
- [CI 全部通过](https://github.com/Ktclat/Pili--/actions/runs/40656052825)，完成 `armeabi-v7a`、`arm64-v8a`、`x86_64` 构建及最终 APK 身份检查。附件仅按 Actions 保留期限提供。
- 使用生产 `MallHttp`、标准 TLS、环境代理及其公开 CA，实际验证推荐两页、手办分类、搜索两页、普通详情与预售详情，**7 个只读联网场景通过**；未登录、下单或付款。

### 安装后的 Android 11 模拟器

实际安装 APK：`0.2.0+3` / x86_64，SHA-256 `1c5cc9b3593de4908d48c8b68a79b1601c7da2867cfab1a752de5cdeaa8c6858`。环境为 Android 11 / API 30 AOSP ATD，软件 CPU 与 SwiftShader；不能据此评估真机性能。

| 操作 | 已观察结果 |
| --- | --- |
| 增量安装与冷启动 | 安装成功，应用可启动，保留应用数据 |
| 与上游双安装 | Pili-- UID 10072、PiliPlus UID 10071；各自私有目录分别为 `/data/user/0/io.github.ktclat.piliminus` 与 `/data/user/0/com.example.piliplus` |
| 原生会员购打开与失败重试 | 出现原生标题、搜索框与可操作的重试按钮，无商城 WebView 节点 |
| 导航隐藏/恢复 | 开关 true → false → true，导航四项 → 三项 → 四项，同一应用进程内立即生效 |
| 隐藏后的入口 | “我的”仍可实际打开独立原生会员购页面 |
| 运行日志 | 本轮采样未见未处理应用异常特征 |

设备内商品请求未成功，**安装后 APK 的联网推荐、搜索和详情未记为通过**。一次标准 `HttpsURLConnection` 探针在 35 秒超时，未能确定具体原因；未添加应用或系统 TLS 绕过。真实响应在主机上的 Flutter 布局预览不计作设备成功。

## 0.1.1+2：稳定性与共存（2026-10-27）

- Flutter **131 项通过**，覆盖下载 200/206/416、落盘长度、暂停取消、完成任务竞态，以及当时的 H5 页面生命周期、URL 信任边界、重定向、重试和稳定 Release 版本比较。
- Python 检查器 **10 项通过**；实际执行 release/debug/`-Pdev` 快捷方式生成，分别包含对应 applicationId 的字面包名。
- [CI 记录](https://github.com/Ktclat/Pili--/actions/runs/40453846560)；框架补丁、锁文件强制模式与源码格式检查通过。

## 0.1.0+1：初始设备验收（2026-10-27）

完整记录、APK 哈希、扫码/视频/权限与相机生命周期证据移至 [历史记录](validation/0.1.0.md)。当时的会员购为按需启用的官方 H5；旧网页截图不能作为 0.2.0 原生页面验收证据。

## 复验与未覆盖范围

按照 [构建指南](BUILD.md) 运行分析、测试、构建和 APK 身份检查。设备采证工具与操作示例见 [历史记录](validation/0.1.0.md#复验)；它只操作安装后的界面，不代替人工验证。双安装操作步骤见 [共存说明](COEXISTENCE.md#真机双安装验收)。

仍待验证：ARM64 真机、安装后 APK 的联网会员购、登录授权、扫码登录、付费账号、长时间播放/下载、低内存和后台恢复、直播长播、投屏、真实订单/支付以及其他操作系统。未建立截图比较或帧率门槛。安全审阅边界见 [SECURITY.md](../SECURITY.md)。
