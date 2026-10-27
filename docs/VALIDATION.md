# Android 验证记录

[返回项目首页](../README.md) · [开发与构建](DEVELOPMENT.md) · [安全说明](../SECURITY.md)

本页保留 Pili-- 在 **2026-10-27（Asia/Hong_Kong）** 已有的 Android 验收记录，来源是主分支提交 [`53f5836`](https://github.com/Ktclat/Pili--/blob/53f58368a0f3852392104dbb7c2db0264f4b6a19/docs/VALIDATION.md) 中的原文。本轮文档整理没有重新运行下述 APK 验收，也没有将其他分支或未合并 PR 的结果计入本页。

这些记录属于本分支的有限环境验证，不代表全部上游功能、真实支付流程或整个供应链通过审计。功能和依赖发生变化后，应按新的提交、安装包与设备重新记录结果，不应把历史的“通过”直接套用到新版本。

## 结果概览

| 验证层级 | 这份历史记录覆盖的范围 |
| --- | --- |
| 构建 | 本地 x86_64、ARM64 的 Release 模式测试签名 APK |
| 安装运行 | Android 16 / API 36 / x86_64 模拟器，游客模式 |
| 业务操作 | 首页、一个公开视频短时播放、扫码、会员购浏览及断网恢复 |
| 静态分析与回归 | 无 error/warning，99 条 info；9 项测试通过 |
| 尚未覆盖 | ARM64 真机、登录与付费账号、真实订单/支付、长时间运行、其他平台等 |

“Release 模式”描述编译配置，不能等同于已完成验收的正式发行版。

## 安装包与环境

- 基于 PiliPlus `72ec31edd6b34883f13ba8caf4e4d76e548ce884`，保留 Git 历史和 GPL v3。
- Flutter 3.47.8 / Dart 3.13.7，项目内隔离 SDK、固定提交依赖、上游框架补丁；JDK 17。
- Release 模式，版本 `0.1.0+1`，包名 `io.github.ktclat.piliminus`。本地 APK 使用测试签名，未嵌入提交号（关于页显示 N/A）；不是正式签名发行包。
- 实际安装：独立 AVD `pili_minus_acceptance_api36`，Android 16 / API 36 / x86_64，系统 WebView 133.0.6943.137，游客账号，虚拟相机和 SwiftShader。
- ARM64 包完成构建与校验，未在 ARM64 真机上运行。其他平台未验证。

原记录保存的本地安装包 SHA-256 如下。安装包没有嵌入提交号，不能仅凭关于页反查它的精确源码版本；这些哈希是历史产物标识，不是后续重新构建的预期值。CI 构建会嵌入自身提交号和构建时间，哈希可以不同。

| 文件 | SHA-256 |
| --- | --- |
| app-x86_64-release.apk | `19b62d1f543c7f4e066ffc23570a3bd9f7e93f1c5b378267175fda2134a4d22e` |
| app-arm64-v8a-release.apk | `b3c34e673ccc507501314316763607302a83afbb0ce60e36b39ab518ae721cdb` |

## 当时实际执行的操作

使用真实 API、CameraX/ML Kit、Android 相册选择器和系统 WebView，没有替换应用服务或伪造商品/视频响应。

| 场景 | 实际结果 |
| --- | --- |
| 全新安装、游客启动、首页/我的切换 | 正常进入首页，真实推荐、封面、我的入口可见 |
| 官方视频二维码 | 显示确认框，主动打开后进入 `BV1xx411c7mD` 视频详情 |
| 视频播放与弹幕 | 点击播放后出现实际视频画面和弹幕，进度由 0% 推进到 19%；只验证此公开视频短时播放 |
| 相机实时识别 | 虚拟场景中摆放实际二维码，CameraX 帧经 ML Kit 识别后弹出正确链接；[截图](validation/camera-qr.png) |
| 相册识别 | 官方链接、普通文本、仿冒域名、JavaScript 字符串均正确分类；空白图片提示未找到二维码 |
| 危险协议 | `javascript:alert(1)` 只有继续/复制按钮，没有打开操作；[截图](validation/unsafe-qr.png) |
| 仿冒域名 | `https://bilibili.com.example.org/...` 标识为外部网站，不视为官方链接；未实际访问该测试域名 |
| 拒绝相机权限 | 保留相册识别与重试入口；识别结束不再自动重复申请；主动点击重试才重新申请 |
| 断网识别 | 关闭模拟器 Wi-Fi/移动数据后，相册二维码仍正常解码；无需首次联网下载识别模型 |
| 相机生命周期 | 扫码页有活动客户端；切后台后无客户端；恢复前台后重建；退出页面后原生相机完成关闭；[系统记录](validation/camera-lifecycle.txt) |
| 会员购首次使用 | 展示下载说明；点击启用后实际下载官方 H5，商品首页正常显示；[截图](validation/mall.png) |
| 会员购浏览与状态 | 分类页可打开、工具栏网页后退有效；离开再进入记住启用；停用返回说明页 |
| 会员购断网与恢复 | 断网显示失败与重新下载按钮；[截图](validation/mall-offline.png)。恢复 Wi-Fi 连接后点击重新下载，真实商品重新显示 |
| 最终 APK Manifest | 包名正确，相机硬件非必需，备份关闭，不含 BiliDocumentsProvider；剩余文件共享 Provider 未导出 |
| 运行日志 | 本轮实际操作未发现应用的 FATAL EXCEPTION、未处理 Flutter 异常或 ANR；WebView 销毁时的 renderer termination 日志不等于应用崩溃 |

相机测试中使用 SDK 自带虚拟场景，墙面放置由 `scripts/android_acceptance.py fixtures` 生成的二维码；经模拟器认证的 gRPC 接口调整物理位置到 `(-2.3, 0.32, 2.72)`、旋转到 `(0, -150, 0)` 后完成实时识别。它验证了相机帧到结果的真实路径，但不能替代真机对焦、弱光和不同镜头测试。

## 当时验收中修复的问题

1. 相机权限被拒后，相册识别结束重新启动相机会再次申请权限：改为显式重试才申请，并补齐拒绝提示。
2. 会员购已显示商品却在 35 秒后误报下载超时：插件创建/加载回调使用不同 Dart 包装对象，改为比较底层平台控制器，保留旧页面回调防护。重建、重新安装后复测通过。
3. 初次 Android 构建受 Windows 空格路径、Git 长路径和原生库下载限制影响：使用隔离 SDK/缓存、可选盘符映射、固定 SHA-256 的原生库预下载；最终两个 ABI 均构建成功。
4. 干净 Linux CI 的原生回归测试缺少 GTK/X11/Xi 开发库：补齐主机依赖，保留测试步骤，不通过跳过检查来消除失败。

## 当时的辅助检查与性能范围

- `flutter analyze --no-pub --no-fatal-infos`：退出码 0；无 error/warning，保留 99 条上游风格、弃用及生成代码 info。
- `flutter test --no-pub`：9 项通过（账号删除后迟到响应不可恢复账号，以及音视频质量选择）。修正现有账号测试的 Hive 初始化，没有移除断言或增加自证实现的测试。
- `git diff --check`：通过。GPL 许可证正文未改动。
- 性能改动集中于相机后台停止/退出释放、会员购按需创建和释放、网页缓存复用、限制无意义重试。没有设置截图基线、帧率基线或用单元测试冒充成品性能验收。
- 模拟器使用软件 GPU，主机同时参与构建。没有据此宣称帧率提升百分比、真机不卡顿或内存泄漏已被完全排除；仍需在目标手机执行长时间播放、滚动、后台切换和低内存测试。

## 如何复验并补充记录

先按[开发与构建指南](DEVELOPMENT.md)准备环境，构建并安装 APK。复验时记录源码提交、APK 的 SHA-256 与签名类型、设备型号/ABI、系统和 WebView 版本、网络条件、账号状态和操作结果；不要只写“已通过”。

仓库提供 [scripts/android_acceptance.py](../scripts/android_acceptance.py) 辅助采集界面证据。它要求 Python 3、可用的 `adb`，以及已授权调试的设备。以下示例在 Windows 的 PowerShell 中运行，`$deviceSerial` 应替换为 `adb devices` 列出的实际序列号：

```powershell
adb devices
$deviceSerial = 'emulator-5556'
python -m venv .tools/acceptance-python
./.tools/acceptance-python/Scripts/python -m pip install qrcode Pillow
$env:PYTHONIOENCODING = 'utf-8'
./.tools/acceptance-python/Scripts/python scripts/android_acceptance.py --serial $deviceSerial fixtures
./.tools/acceptance-python/Scripts/python scripts/android_acceptance.py --serial $deviceSerial snapshot home
./.tools/acceptance-python/Scripts/python scripts/android_acceptance.py --serial $deviceSerial tap 扫一扫
```

Linux 主机创建虚拟环境后，对应 Python 路径为 `.tools/acceptance-python/bin/python`。`qrcode` 和 Pillow 用于生成测试图片；截图和点击操作依赖 `adb`。

工具的 `fixtures` 会生成二维码素材、写入设备的 `/sdcard/Pictures/PiliMinusAcceptance/` 并触发媒体扫描；`snapshot` 保存当前界面的 XML 与截图；`tap` 会真实点击可见控件。脚本没有内置清除账号数据、登录、下单或付款流程，采证时仍应确认所处页面和所点击的控件。

### 证据保存

`docs/validation/` 中现有的四张截图与相机生命周期日志属于上述历史验收，不是自动截图比较基线。本机完整过程材料原记录在被 Git 忽略的 `.artifacts/acceptance/`，它不随仓库提供。新增记录时请选择与结论直接相关的脱敏证据，按日期或版本建立新目录，保留旧记录。

每条新结果应区分“通过”“失败”“未执行”与“受环境限制”，并列出仍未验证的项目。修改文档或通过代码检查，不应改变过去 APK 的验收结论。

## 未验证范围

登录授权、付费账号、会员权限、真实购物订单/支付、扫码登录授权、下载任务长时间运行、直播长播、投屏、全部上游业务、ARM64 真机及其他操作系统均未完成验收。会员购目前是按需加载的官方 H5，未实现可单独安装的原生动态模块。安全审阅的边界见 [SECURITY.md](../SECURITY.md)。
