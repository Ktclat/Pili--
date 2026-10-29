# 安装与升级

[项目首页](../README.md) · [构建指南](BUILD.md) · [共存说明](COEXISTENCE.md)

## 获取测试包

当前版本 `0.4.0+5` 尚未发布正式 Release。测试包从本仓库的 [Android validation build](https://github.com/Ktclat/Pili--/actions/workflows/build.yml) 获取：

1. 选择目标分支和提交对应的 **成功** 运行。`main` 是已整合代码，PR 构建用于验证尚未合并的改动。
2. 在运行页面底部的 **Artifacts** 下载 `Pili--Android-test-signed`。GitHub 要求登录后下载，附件默认保留 14 天。
3. 解压 ZIP，按下表选择一个 APK。不要把整个 ZIP 当作安装包。
4. 通过 Android 安装界面安装；按系统提示为使用的文件管理器或浏览器授予安装来源权限。

| APK | 适用设备 |
| --- | --- |
| `app-arm64-v8a-release.apk` | 多数当前 Android 手机，建议优先确认此架构 |
| `app-armeabi-v7a-release.apk` | 支持 32 位 ARM 的设备 |
| `app-x86_64-release.apk` | x86_64 Android 设备或模拟器 |

最低 Android 版本为 **7.0 / API 24**。不确定架构时可查看设备资料；开发者可运行 `adb shell getprop ro.product.cpu.abilist`。构建标为 `release` 仅指编译模式，CI 包仍使用测试签名。

附件过期时，从较新的成功构建获取测试包，或按 [构建指南](BUILD.md) 自行构建。取消或失败的运行不能视为已验证版本。应用内检查更新只读取正式稳定 Release，因此目前提示没有正式发行版是正常行为。

## 与 PiliPlus 一起使用

Pili-- 使用 `io.github.ktclat.piliminus`，上游 PiliPlus 使用 `com.example.piliplus`。可以保留上游后安装本项目，账号、设置和默认离线目录各自独立，不自动导入上游账号。

两者可能同时接收 B 站通用链接，由系统默认打开方式决定。可在 Android 的“应用 → 默认打开方式”调整。共存实现与验证范围见 [COEXISTENCE.md](COEXISTENCE.md)。

## 从旧版升级

0.4.0 移除会员购与 UP 主页小店，默认导航恢复为首页、动态、我的。旧导航里的已删除项目会被忽略，保留有效项目的顺序与隐藏状态；若原来只保留了已删除项目，则恢复默认导航。

启动时清理旧商品收藏、浏览足迹及相关开关，不再打开对应存储。视频收藏、播放历史、账号与下载记录不受这项清理影响。使用旧版商店作为启动页时会安全回退到可用页面。

## 签名与覆盖升级

覆盖升级需要相同安装 ID、相同签名，并满足 Android 的版本号要求。临时 CI Runner 使用的测试密钥可能不同；版本相同不代表签名相同。

遇到“与现有软件包冲突”或签名不匹配时，先核对包来源与错误信息。不要为解决 Pili-- 的签名问题卸载 PiliPlus，也不要未经备份就清除 Pili-- 数据。正式分发前需要配置并长期保存固定的发行签名密钥，目前不承诺不同 CI 测试包互相覆盖升级。

测试包仍需真机验收；已执行与未执行的范围见 [验证记录](VALIDATION.md)。反馈请附应用版本/提交、下载的 Actions 链接、设备型号与 Android 版本。
