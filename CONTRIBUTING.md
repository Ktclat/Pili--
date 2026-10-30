# 参与贡献

本仓库维护 Pili-- 的 Android 改进。问题与 PR 请提交到 [Ktclat/Pili--](https://github.com/Ktclat/Pili--)；保留上游项目链接用于说明来源，不将本项目特有问题自动转给上游。

[常见问题](docs/FAQ.md) · [开发导览](docs/DEVELOPMENT.md) · [来源与致谢](docs/ACKNOWLEDGEMENTS.md)

## 反馈问题

先搜索[已有问题](https://github.com/Ktclat/Pili--/issues?q=is%3Aissue)，再使用 [Bug 反馈或功能请求表单](https://github.com/Ktclat/Pili--/issues/new/choose)。请提供版本/构建提交、安装来源、设备、复现步骤、实际行为与预期行为。无法排除网络或账号问题时如实描述即可，无需先作结论。

日志和截图请移除 Cookie、access_key、二维码登录凭据、手机号及订单信息。安全漏洞请先阅读 [安全报告说明](SECURITY.md)，不要在公开 Issue 中提交漏洞细节。

## 修改代码

1. 从目标基线创建自己的分支，阅读 [构建指南](docs/BUILD.md)，准备隔离 SDK、缓存、补丁与锁文件。
2. 保持改动聚焦；说明会影响的用户行为和边界。包身份参考 [共存说明](docs/COEXISTENCE.md)。
3. 对下载、导航、请求生命周期等逻辑改动运行相关回归测试；需要新增覆盖时测试真实风险和行为。纯文档修改检查链接、命令和版本一致性。
4. 提交前检查差异；涉及源码时使用构建指南中的分析和测试命令。CI 会执行全量测试、三架构 APK 构建及安装包身份检查。
5. PR 中说明最终行为、验证结果和仍未覆盖的设备场景。更新相关文档及 [CHANGELOG.md](CHANGELOG.md)，不要把旧 APK 的结果套用到新提交。

## 项目约定

- 保留 `io.github.ktclat.piliminus` 安装 ID 及变体隔离；JNI 使用的 `com.example.piliplus` 内部名称不可全局替换。
- 使用已提交的 `pubspec.lock`；主动更新依赖时才使用 `prepare_android.ps1 -UpdateLockfile` 并审阅差异。不要提交 `.tools/`、`.artifacts/`、签名密钥或本机配置。
- 保持标准 TLS，不向非目标服务附加账号凭据。不要记录或公开完整账号请求。
- 保留 GPL 与依赖版权声明，提供所修改部分的对应源码；来源见 [NOTICE](NOTICE)。

维护者整合时应核对目标提交的检查结果。正式 Release 还需要固定签名、可追溯源码与实际设备验收，不能仅凭 CI 构建成功发布为已验收成品。

## 来源与上游同步

复用上游或第三方的代码、补丁、素材时，记录原始仓库与提交并保留署名和许可。PiliPlus 是直接上游；本项目的改动与反馈由本仓库独立维护，不将上游贡献者描述为本项目维护团队。个人兴趣与自用的定位不增加额外许可限制，具体权利遵循相应许可证。
