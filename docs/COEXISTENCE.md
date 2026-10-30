# Android 与 PiliPlus 共存

Pili-- 使用独立的 Android 安装包身份，可与上游 PiliPlus 分别安装。本文区分源码/安装包检查与真机双安装验收；自动配置检查通过不等于所有设备已经实测。

## 身份与数据边界

| 项目 | Pili-- | PiliPlus 上游 |
| --- | --- | --- |
| release applicationId | `io.github.ktclat.piliminus` | `com.example.piliplus` |
| debug applicationId | `io.github.ktclat.piliminus.debug` | `com.example.piliplus.debug` |
| `-Pdev` release applicationId | `io.github.ktclat.piliminus.dev` | `com.example.piliplus.dev` |
| 应用名 | Pili--；debug/dev 附加后缀 | PiliPlus |

上游依据为本项目继承的 [PiliPlus `72ec31ed` Android 构建配置](https://github.com/bggRGjQaUbCoE/PiliPlus/blob/72ec31edd6b34883f13ba8caf4e4d76e548ce884/android/app/build.gradle.kts)。独立 applicationId 使 Android 分配独立应用 UID、私有目录与卸载范围，安装 Pili-- 不会作为 PiliPlus 的升级包覆盖它。

- 保留 Java/Kotlin 的 `com.example.piliplus` namespace、`MainActivity` 和 JNI 绑定类名。这是代码内部名称，不是最终安装 ID。盲目全局替换会破坏 `bindings.g.dart`、原生类查找和混淆保留规则。
- 未声明 `sharedUserId`。Hive 账号、设置和记录位于 `getApplicationSupportDirectory()` 下；临时目录、WebView Cookie/缓存属于各自应用沙箱。
- Android 离线视频使用 `getExternalStorageDirectory()/download`，其父目录由系统按实际安装包名提供，不指向上游下载目录。
- 主动保存到相册的图片位于 `Pictures/Pili--`。这是用户可见的公共媒体；卸载后可能保留，不能当作账号私有存储。
- Manifest 明确关闭 `allowBackup` 和 `fullBackupContent`。未加入账号自动导入或读取上游私有目录的逻辑；用户主动导入配置文件应另行选择来源。
- 私有存储的 `BiliDocumentsProvider` 已移除。依赖库合并的共享文件 Provider 必须不导出，并使用最终 applicationId 前缀的 authority；构建后检查会验证实际合并结果，而不只看主 Manifest。
- 通知 channel ID 即使沿用上游字符串，也由 Android 按应用 UID 隔离；Java 类名和应用内 method channel 同样不会跨进程共享。

## 链接与桌面快捷方式

普通 B 站网页和 `bilibili://` 链接是共用协议。两个客户端同时安装时，由 Android 的“默认打开方式”和用户选择决定接收者；Pili-- 不设置 `autoVerify` 抢占上游默认链接。可在系统“应用 → 默认打开方式”调整。

原来的静态快捷方式沿用上游私有 `SHORTCUT` action，动态固定快捷方式只有 URI，没有目标组件。双安装时存在解析到另一客户端的风险。本次改为：

- 长按应用图标显示的“搜索/离线视频”快捷方式，使用显式 `targetPackage` 与 `targetClass`。
- Gradle 从每个变体的最终 `applicationId` 生成含字面目标包名的快捷方式 XML，因此 `.debug`、`.dev` 不会跳到普通 release。不能给 `targetPackage` 使用 `@string`：Android 的快捷方式 Intent 解析器不会解析该组件资源引用，会生成无法启动的目标包；检查器明确拒绝此类引用。
- 固定到桌面的动态快捷方式使用当前应用 `Context` 和 `MainActivity.class` 创建显式 Intent。
- 移除上游私有 `com.example.piliplus.SHORTCUT` action 注册，保留普通网页和 B 站协议入口。

旧版本已固定到桌面的快捷方式可能由启动器缓存。若升级后旧快捷方式仍弹出选择器，应删除该旧快捷方式，再从 Pili-- 内创建；不要清除或卸载 PiliPlus。

## 签名与升级

不同 applicationId 的应用不需要使用相同签名即可共存。以后更新 Pili-- 自身时，仍须保持同一 applicationId 和签名密钥，并正确递增版本号。

未配置 `android/key.properties` 时生成的是测试签名包。各台开发机器或临时 CI Runner 的调试密钥可能不同，所以不同来源的测试包之间不能保证覆盖升级；首次改用自己的正式密钥，也不能覆盖旧的异签名测试包。签名不匹配时应停止安装并检查来源，不能以卸载 PiliPlus 解决。正式密钥和密码不得提交仓库。

## 自动检查

只需 Python 3 的源码与检查器回归测试：

```sh
python3 scripts/check_android_identity.py
python3 -m unittest discover -s scripts/tests -v
```

构建后检查实际 APK（支持重复 `--apk` 检查多个 ABI）：

```sh
python3 scripts/check_android_identity.py \
  --apk build/app/outputs/flutter-apk/app-arm64-v8a-release.apk \
  --apk build/app/outputs/flutter-apk/app-x86_64-release.apk
```

脚本自动从 `ANDROID_HOME` 或 `ANDROID_SDK_ROOT` 的 `build-tools` 中选择最高版本 `aapt/aapt2`，再尝试 `PATH`。也可显式传入 `--aapt /path/to/android-sdk/build-tools/VERSION/aapt2`；Windows 使用 `python` 和 `.exe` 工具路径。

检查覆盖包身份、共享 UID、任务栈归属、备份配置、全部合并 Provider 的 authority/导出状态、私有权限、编译后的快捷方式目标包与原生 Activity。不读取账号内容，不安装或卸载应用。没有 `--apk` 时只做源码检查，会明确输出未检查依赖合并结果。

## 真机双安装验收

在同一台目标手机保留已安装的 PiliPlus，再安装同 ABI 的 Pili--。遇到安装失败先记录错误，不卸载原客户端。

1. 确认桌面两个应用均存在，分别启动；上游账号、历史与下载仍保留。
2. 分别改变主题或设置，重启两边，确认不会相互改变。Pili-- 首次启动不应继承上游账号。
3. 长按两边图标分别执行“搜索/离线视频”；从 Pili-- 创建固定快捷方式，确认始终回到 Pili--。再对 debug/dev 包重复。
4. 从浏览器打开 B 站链接，验证系统默认/选择器行为；改变一边的默认打开设置不会影响另一边的私有数据。
5. 两边分别播放、下载和保存图片，检查通知、离线文件与图片路径；对同签名的新版本验证覆盖升级。
6. 如需验证卸载隔离，应在已备份且获准操作的测试设备上仅卸载 Pili--，确认 PiliPlus 仍可使用。本检查脚本不会执行该动作。

自动源码检查与检查器回归测试已通过。应用 APK 与模拟器双安装结果按版本记录在对应 CI/PR 中；真机、所有 ABI/Android 版本及完整业务验收仍须记录实际结果，不用以上步骤列表代替已完成的验收。
