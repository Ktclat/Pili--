# 开发工具

[返回首页](../README.md) · [开发与构建](../docs/DEVELOPMENT.md)

这里保存 Pili-- 继承并使用的开发期工具。普通 APK 构建使用已经提交的生成文件，通常不需要手动运行这些工具。

## Android JNI 绑定生成

[`jnigen.dart`](jnigen.dart) 使用 `jnigen` 为以下 Java 类生成 Dart 绑定：

- `com.example.piliplus.AndroidHelper`：源码位于 `android/app/src/main/java/`。
- `java.lang.Runnable`。

工具通过 Android / Gradle 配置读取类路径和依赖，将结果写入并覆盖 [`lib/utils/android/bindings.g.dart`](../lib/utils/android/bindings.g.dart)。生成过程可能解析或下载构建依赖。修改 Java 接口或升级相关工具后，才需要评估是否重新生成。

### 使用步骤

1. 按[开发文档](../docs/DEVELOPMENT.md)准备项目内 Flutter、Pub 缓存、JDK 和 Android SDK。
2. 在仓库根目录确认工作区修改已妥善保存，尤其是现有 `bindings.g.dart`。
3. 在 PowerShell 7 中使用隔离 SDK 自带的 Dart 执行：

```powershell
$env:PUB_CACHE = Join-Path $PWD '.tools/pub-cache'
$dart = Join-Path $PWD '.tools/flutter/bin/dart'
if ($IsWindows) { $dart += '.bat' }
& $dart run tool/jnigen.dart
if ($LASTEXITCODE -ne 0) { throw 'JNI 绑定生成失败。' }
git diff -- lib/utils/android/bindings.g.dart
```

检查生成差异是否仅包含预期的接口变化，再按开发文档运行静态分析、回归测试和 Android 构建。不要手工维护生成文件，也不要仅为了改品牌名称而替换 Java 包路径；当前 JNI 名称与 `AndroidHelper` 等原生类相互关联，Android 的独立安装身份由 applicationId 设置。
