# 安装与升级

[项目首页](../README.md) · [构建指南](BUILD.md) · [共存说明](COEXISTENCE.md)

## 获取预发布测试包

当前版本 `0.5.0+6` 已发布为 [v0.5.0-beta.1](https://github.com/Ktclat/Pili--/releases/tag/v0.5.0-beta.1)，使用 Actions 临时测试签名，尚无固定发行密钥签名的稳定版。

1. 打开上述 Release，在 **Assets** 中按下表下载一个 APK；不要把源码压缩包当作安装包。
2. 下载同页的 `SHA256SUMS.txt`，核对所选 APK 的 SHA-256。
3. `BUILD_INFO.json` 记录实际包身份、签名证书摘要及来源；`PiliMinus-0.5.0+6-source.tar.gz` 提供对应源码和构建材料。
4. 通过 Android 安装界面安装；按系统提示为使用的文件管理器或浏览器授予安装来源权限。

| APK | 适用设备 |
| --- | --- |
| `PiliMinus-0.5.0+6-arm64-v8a-test-signed.apk` | 多数当前 Android 手机，建议优先确认此架构 |
| `PiliMinus-0.5.0+6-armeabi-v7a-test-signed.apk` | 支持 32 位 ARM 的设备 |
| `PiliMinus-0.5.0+6-x86_64-test-signed.apk` | x86_64 Android 设备或模拟器 |

最低 Android 版本为 **7.0 / API 24**。不确定架构时可查看设备资料；开发者可运行 `adb shell getprop ro.product.cpu.abilist`。构建标为 `release` 仅指编译模式，CI 包仍使用测试签名。

开发测试包也可从成功的 [Android validation build](https://github.com/Ktclat/Pili--/actions/workflows/build.yml) 下载：选择目标提交，在 **Artifacts** 获取 `Pili--Android-test-signed` 并解压。Actions 附件需登录 GitHub，默认保留 14 天，其中 APK 使用 `app-<ABI>-release.apk` 命名；这项期限不适用于已上传的 Release 附件。取消或失败的运行不能视为已验证版本。

应用内检查更新只读取稳定 Release，会忽略本次 Pre-release；提示没有稳定发行版时，请从本页链接手动下载。预发布构建来源为提交 `6bb2ef25ac67233881333adb175603d77b602cb7` 和 [本次 Actions](https://github.com/Ktclat/Pili--/actions/runs/41020225007)。

## 与 PiliPlus 一起使用

Pili-- 使用 `io.github.ktclat.piliminus`，上游 PiliPlus 使用 `com.example.piliplus`。可以保留上游后安装本项目，账号、设置和默认离线目录各自独立，不自动导入上游账号。

两者可能同时接收 B 站通用链接，由系统默认打开方式决定。可在 Android 的“应用 → 默认打开方式”调整。共存实现与验证范围见 [COEXISTENCE.md](COEXISTENCE.md)。

## 扫码授权与链接识别

- “我的 → 扫码授权登录”：扫描你本人设备上的网页或 TV 登录码，核对当前账号与登录位置，再明确确认授权。未登录时先登录并重新扫码；额外验证由官方处理。
- “我的 → 识别链接”：手动输入或主动粘贴分享文字、B 站链接及 BV/av；识别后确认打开。
- Android 系统分享面板可选择 Pili--，接收 `text/plain` 分享。隐私设置中的接收开关默认开启。
- 隐私设置中的自动剪贴板识别默认关闭；开启后进入前台读取。同内容提示会去重，关闭后不再自动读取。手动粘贴按钮是单次主动操作。

## 从旧版升级

0.4.0 移除会员购与 UP 主页小店，默认导航恢复为首页、动态、我的。旧导航里的已删除项目会被忽略，保留有效项目的顺序与隐藏状态；若原来只保留了已删除项目，则恢复默认导航。

启动时清理旧商品收藏、浏览足迹及相关开关，不再打开对应存储。视频收藏、播放历史、账号与下载记录不受这项清理影响。使用旧版商店作为启动页时会安全回退到可用页面。

## 签名与覆盖升级

覆盖升级需要相同安装 ID、相同签名，并满足 Android 的版本号要求。临时 CI Runner 使用的测试密钥可能不同；版本相同不代表签名相同。

遇到“与现有软件包冲突”或签名不匹配时，先核对包来源与错误信息。不要为解决 Pili-- 的签名问题卸载 PiliPlus，也不要未经备份就清除 Pili-- 数据。正式分发前需要配置并长期保存固定的发行签名密钥，目前不承诺不同 CI 测试包互相覆盖升级。

预发布包仍需 ARM64 真机及真实账号网页／TV 授权验收；已执行与未执行的范围见 [验证记录](VALIDATION.md)。反馈请附应用版本/提交、下载的 Release 或 Actions 链接、设备型号与 Android 版本。
