# iOS 启动画面资源

[返回 Pili-- 首页](../../../../README.md) · [来源与致谢](../../../../docs/ACKNOWLEDGEMENTS.md)

本目录保留自上游的 iOS 启动画面资源。Pili-- 当前重点维护和验证 Android；保留这些文件不表示已经提供可安装的 iOS 版本，也不表示 iOS 签名、构建或启动流程已通过验收。

## 资源对应关系

[`Contents.json`](Contents.json) 定义普通与深色外观各三个倍率的图片：

| 外观 | 1× | 2× | 3× |
| --- | --- | --- | --- |
| 普通 | `LaunchImage.png` | `LaunchImage@2x.png` | `LaunchImage@3x.png` |
| 深色 | `LaunchImageDark.png` | `LaunchImageDark@2x.png` | `LaunchImageDark@3x.png` |

需要开展 iOS 适配时，可替换相应图片并保持文件名和倍率映射一致；也可在 macOS 的仓库根目录打开 Xcode 工作区：

```bash
open ios/Runner.xcworkspace
```

在 Xcode 中选择 `Runner/Assets.xcassets`，检查普通、深色外观和各倍率。仓库的 `pubspec.yaml` 还包含 `flutter_native_splash` 配置；如果使用该生成器，应一并审阅相关资源和原生配置的变动，避免下次生成覆盖手工修改。

提交新资源时说明来源、许可与设计变更，保留原有版权声明。仅替换图片不会完成 iOS 应用身份、签名和发布配置；相关平台工作需要单独构建与设备验收。
