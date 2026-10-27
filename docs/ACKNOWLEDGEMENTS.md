# 来源与致谢

[返回项目首页](../README.md) · [English overview](../README.en.md) · [来源声明](../NOTICE) · [许可证](../LICENSE)

Pili-- 是基于 **PiliPlus** 继续修改、独立维护的个人兴趣 fork，用来学习 Flutter、满足自己的使用习惯，也试着做一些好玩的功能。它建立在许多开发者已经完成的工作之上。感谢这些项目的作者、贡献者，以及分享反馈、修复和文档的人。

## 项目的来处

| 项目 | 与 Pili-- 的关系 |
| --- | --- |
| [PiliPlus](https://github.com/bggRGjQaUbCoE/PiliPlus) | **直接上游**。Pili-- 继承其客户端基础、现有功能、平台工程与提交历史，并在此基础上继续开发。 |
| [PiliPala](https://github.com/guozhigq/pilipala) | PiliPlus 明确致敬的原始项目，为这一系列 Flutter 客户端奠定了基础。 |
| [PiliPalaX](https://github.com/orz12/PiliPalaX) | PiliPlus 明确致敬的上游项目，其工作通过后续项目被继承。 |

本仓库记录的初始导入基线为 PiliPlus 提交 [`72ec31e`](https://github.com/bggRGjQaUbCoE/PiliPlus/commit/72ec31edd6b34883f13ba8caf4e4d76e548ce884)（完整 SHA：`72ec31edd6b34883f13ba8caf4e4d76e548ce884`）。来源说明可对照[该版本的上游 README](https://github.com/bggRGjQaUbCoE/PiliPlus/blob/72ec31edd6b34883f13ba8caf4e4d76e548ce884/README.md)及本仓库的 [NOTICE](../NOTICE)。

Pili-- 自行维护功能取舍、文档、问题反馈与后续发布。它不是上述项目维护团队发布的官方版本，也不是哔哩哔哩官方客户端。上游作者没有因为代码被继承而自动成为本项目的维护者。

## 如何理解提交记录和 Contributors

本仓库保留了上游 Git 历史，因此在提交记录和 GitHub Contributors 中看到上游作者，是代码来源得到保留的结果。这些记录表示他们对被继承代码的贡献，**不表示他们加入了 Pili-- 的维护团队，也不表示他们认可本项目后续的每项改动**。

- 原有提交、作者信息、文件版权声明与许可证继续保留。
- Pili-- 新增或修改的内容通过本仓库的新提交记录，具体作者以提交记录为准。
- 项目介绍区分继承能力与本项目改动，不把上游已经实现的功能描述为本项目原创。
- 使用 Pili-- 遇到的问题请先提交到[本仓库 Issues](https://github.com/Ktclat/Pili--/issues)，附上 Pili-- 的版本和复现步骤。如果确认同样影响上游，再提供针对上游的最小复现。

感谢[本仓库历史贡献者](https://github.com/Ktclat/Pili--/graphs/contributors)与 [PiliPlus 贡献者](https://github.com/bggRGjQaUbCoE/PiliPlus/graphs/contributors)。贡献记录会随开发继续积累，本页不把历史作者列表当作当前维护团队名单。

## 开源生态与参考项目

以下列出直接依赖、重要基础设施和上游已注明的参考来源；这是致谢索引，完整依赖以 [`pubspec.yaml`](../pubspec.yaml)、[`pubspec.lock`](../pubspec.lock) 及对应版本源码为准。

| 项目 | 致谢缘由 |
| --- | --- |
| [Flutter](https://github.com/flutter/flutter) / [Dart](https://github.com/dart-lang/sdk) | 客户端使用的界面框架、语言与工具链。 |
| [bilibili-API-collect](https://github.com/SocialSisterYi/bilibili-API-collect) | 上游致谢的社区接口资料整理项目。 |
| [flutter_meedu_videoplayer](https://github.com/abdelaziz-mahdy/flutter_meedu_videoplayer) | 上游已注明的播放器参考项目（原 `zezo357` 仓库地址已迁移）；此处保留来源致谢，不将其描述为当前直接依赖。 |
| [media-kit](https://github.com/media-kit/media-kit) | 播放器基础，以及当前依赖使用的社区修改版本。 |
| [Dio](https://github.com/cfug/dio) / [cookie_jar](https://github.com/flutterchina/cookie_jar) | HTTP 请求与 Cookie 管理相关基础组件。 |
| [mobile_scanner](https://github.com/juliansteenbakker/mobile_scanner) | 扫一扫功能使用的二维码识别组件。 |
| [flutter_inappwebview](https://github.com/pichillilorenzo/flutter_inappwebview) | 内嵌网页相关组件，以及当前依赖使用的社区修改版本。 |

也感谢 [bggRGjQaUbCoE](https://github.com/bggRGjQaUbCoE)、[My-Responsitories](https://github.com/My-Responsitories) 及其他依赖维护者持续提供的修改版本。实际使用的仓库、提交和覆盖配置以依赖文件为准；本页不声称列出了全部贡献者。

## 许可证、素材与署名

根目录保留上游的 [GPL v3 许可证全文](../LICENSE)。Pili-- 修改的许可说明见 [NOTICE](../NOTICE)；已有文件和第三方组件继续遵循各自适用的许可及版权声明。个人兴趣、学习与自用是项目的开发目的，具体使用、修改与分发权利以相应许可证为准。

仓库中还保留了以下组件的独立声明：

| 位置 | 原有声明 |
| --- | --- |
| [`assets/shaders/LICENSE`](../assets/shaders/LICENSE) | MIT；Copyright (c) 2019 bloc97。 |
| [`lib/utils/accounts/account_manager/LICENSE`](../lib/utils/accounts/account_manager/LICENSE) | MIT；Copyright (c) 2018 Wen Du (wendux) 与 Copyright (c) 2022 The CFUG Team。 |
| 应用内开源许可证页面 | Flutter 生成的依赖许可登记；第三方源码中的声明同样需要保留。 |

当前沿用的图标与部分平台资源来自上游；保留素材不表示它们由 Pili-- 原创，也不表示获得相关项目或哔哩哔哩的官方背书。后续更换视觉设计时，也应保留仍在使用的第三方素材及代码的来源说明。

再次感谢每一个愿意分享代码、经验与时间的人。Pili-- 会在保留这些来处的基础上，继续做自己的小实验。
