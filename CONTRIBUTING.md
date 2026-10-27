# 参与 Pili--

感谢你愿意帮这个个人兴趣项目变得更好。Pili-- 基于 [PiliPlus](https://github.com/bggRGjQaUbCoE/PiliPlus) 独立维护，主要面向 Android 上的自用体验和功能实验。问题反馈、文档修正、复现记录和代码改进都欢迎；维护者会结合精力与项目方向决定是否推进，不承诺处理或发布时限。

[项目首页](README.md) · [常见问题](docs/FAQ.md) · [开发与构建](docs/DEVELOPMENT.md) · [来源与致谢](docs/ACKNOWLEDGEMENTS.md)

## 报告问题

先搜索[本仓库的历史 Issues](https://github.com/Ktclat/Pili--/issues?q=is%3Aissue)，再选择 [Bug 模板](https://github.com/Ktclat/Pili--/issues/new?template=bug-%E5%8F%8D%E9%A6%88.yml)。尽可能提供：

- Pili-- 版本、提交号和安装来源；源码构建请注明是否有本地修改。
- 设备型号、Android 版本；扫码或网页问题补充相机权限、系统 WebView 版本等相关信息。
- 最短复现步骤、期望行为与实际行为，注明发生频率和影响范围。
- 必要的截图、录屏或脱敏日志；涉及视频时，可提供公开可访问的 BV / av 标识。
- 你已经尝试过的排查，以及无法确认的部分。无需为了提交报告断言“已排除所有网络或账号问题”。

可从“设置 → 关于”查看版本、提交信息和错误日志。`N/A` 表示构建未写入提交号，并不代表没有源码；请提供下载时对应的 Actions 运行或本地 `git rev-parse HEAD` 结果。

**不要上传 Cookie、access_key、密码、登录二维码、账号导出文件、私有设置备份或订单个人信息。** 安全漏洞按 [SECURITY.md](SECURITY.md) 反馈，不在公开 Issue 中发布可被利用的细节。

Pili-- 的改动和安装包优先在本仓库讨论。只有在未修改的上游版本中也能复现、且确实需要上游处理时，再整理独立复现报告；不要自动向多个项目重复提交同一问题。

## 提出功能

使用[功能请求模板](https://github.com/Ktclat/Pili--/issues/new?template=%E5%8A%9F%E8%83%BD%E8%AF%B7%E6%B1%82.yml)，先描述使用场景和想解决的问题，再给出可能的方案。请区分“当前缺陷”和“新的行为偏好”，说明是否涉及账号权限、额外服务、后台任务或较大的依赖。

较大的功能建议先在 Issue 中沟通范围，减少不必要的返工。被讨论或列入 Issue 不代表已经确定实施；发布说明和已合并代码才是功能状态的依据。

## 提交改动

1. 从本仓库 `main` 创建有明确用途的分支；构建环境按[开发指南](docs/DEVELOPMENT.md)准备。
2. 一个 PR 尽量解决一个清楚的问题。避免把功能修复、无关格式调整和大量依赖升级混在一起。
3. 说明为什么需要改动、改动后的行为和实际验证结果。界面变化附截图或录屏；未验证的设备、平台和场景明确写出。
4. 涉及可观察行为的修复，应在适当层级补充能复现问题的回归验证；纯文档修改检查内容、链接和示例即可，不必为此重跑完整 APK 构建。
5. 向 [Ktclat/Pili--](https://github.com/Ktclat/Pili--) 的 `main` 提交 Pull Request。若基于另一个未合并分支开发，明确标注依赖关系。

源码改动常用的检查命令：

```powershell
$env:PUB_CACHE = Join-Path $PWD '.tools/pub-cache'
./.tools/flutter/bin/flutter analyze --no-pub --no-fatal-infos
./.tools/flutter/bin/flutter test --no-pub
git diff --check
```

上述命令应在准备脚本成功执行后运行。需要验证 Android 行为时，再构建、安装并实际操作 APK。分析通过、测试通过和真机验收是不同证据，请分别记录。

## 代码与文档约定

- 沿用改动附近已有的 Dart、Flutter 和目录风格，尽量缩小修改范围。
- 保留 `pubspec.lock`；修改依赖时一并说明来源、版本、许可及必要性。不要在普通功能 PR 中批量刷新所有依赖。
- 不提交签名密钥、`android/key.properties`、账号资料、本机 SDK、缓存、APK 或完整调试产物。
- 对外功能说明以当前分支实际实现为准。同步修改中英文 README 和相关指南，避免只更新一个入口。
- 不把未合并 PR、计划或旧验收结果写成当前版本已完成的工作；验证记录注明日期、环境、源码版本和未覆盖项。
- 不以“个人项目”为理由删除作者署名、许可或来源；也不把上游历史贡献者列成自己的维护团队。

## 同步上游与复用代码

PiliPlus 是直接上游。同步时明确记录源仓库和提交，保留原始作者信息与版权声明；如果改写实现或处理冲突，在提交说明中交代。避免为改变 Contributors 展示而清空历史或批量改写作者。

引入其他项目的代码、补丁或素材时，核对其许可并保留必要声明，同时更新 [NOTICE](NOTICE) 或[致谢文档](docs/ACKNOWLEDGEMENTS.md)。已有 MIT 等独立许可文件应继续保留。贡献不改变第三方材料原有的许可要求。

新贡献遵循本项目及相应文件的许可约定，详见 [LICENSE](LICENSE) 和 [NOTICE](NOTICE)。沟通时围绕可复现的问题和具体方案，尊重不同项目的维护边界与贡献者的时间。
