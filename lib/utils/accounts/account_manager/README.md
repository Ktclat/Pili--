# 账号请求拦截器

[返回首页](../../../../README.md) · [安全说明](../../../../SECURITY.md) · [来源与致谢](../../../../docs/ACKNOWLEDGEMENTS.md)

本目录中的 [`account_mgr.dart`](account_mgr.dart) 是 Pili-- 使用的账号请求拦截器。代码由上游基于 **dio_cookie_manager** 修改而来，并继续适配本项目的账号模型与请求策略；这里不再作为通用 `dio_cookie_manager` 包的安装指南。

## 来源与许可

- 原始组件：[dio_cookie_manager](https://pub.dev/packages/dio_cookie_manager)，用于连接 Dio 请求拦截器与 Cookie 管理。
- 原版权声明：**Copyright (c) 2018 Wen Du (wendux)**、**Copyright (c) 2022 The CFUG Team**。
- 本目录保留原 [MIT 许可证](LICENSE)。它与项目根目录的 [GPL v3 许可证](../../../../LICENSE) 一并保留，不能因整理项目名称而删除。
- 后续适配来源可通过本文件和 `account_mgr.dart` 的 Git 历史追溯。感谢原作者、PiliPlus 及后续维护者。

## 模块职责

`AccountManager` 继承 Dio 的 `Interceptor`，与 [`Account`](../account.dart)、[`Accounts`](../../accounts.dart) 和 [`ApiType`](../api_type.dart) 协作：

| 阶段 | 当前职责 |
| --- | --- |
| 请求前 | 判断目标地址、绑定本次请求的账号，并按 API 类型添加 Cookie、请求头或 App 签名参数 |
| 响应后 | 解析 `Set-Cookie`，写回该次请求绑定账号的 CookieJar，再触发账号持久化 |
| 请求失败 | 在适用情况下处理响应 Cookie，并显示经过处理的错误提示 |
| 账号删除 | 与账号模型协作，避免已删除账号被迟到响应重新持久化 |

`cookie_jar` 管理 Cookie 的域、路径及请求匹配；常规 `CookieJar` 使用内存，`PersistCookieJar` 提供基于文件的持久化能力。**本项目的登录账号使用自己的账号模型和 Hive 存储链路**，不能把通用包示例中的 `PersistCookieJar` 直接当作这里的实际存储方案。具体行为见 [`account.dart`](../account.dart) 与 [`accounts.dart`](../../accounts.dart)。

## 请求与重定向边界

当前实现通过 [`TrustedUrl`](../../trusted_url.dart) 检查账号请求目标：HTTPS、443 端口、无 URL 用户信息，主机为 `bilibili.com` 或其子域。未通过检查的请求不会在此附加哔哩哔哩账号；拦截器会移除 Cookie、Authorization 和 `x-bili-*` 请求头。

带账号请求关闭底层自动重定向，由 [`RetryInterceptor`](../../../http/retry_interceptor.dart) 审查重定向目标。该逻辑拒绝跨源跳转，避免把请求体、凭据或签名查询转交其他来源；它与网络失败时只自动重试 GET / HEAD 的规则分别处理。不要恢复通用示例中“读取 `Location` 后直接携带原请求信息继续访问”的做法。

这些说明描述当前模块的实现边界，不表示所有网络路径或依赖已经通过完整审计。新增 API、改变账号选择、Cookie 保存或重定向行为时，应同时审查请求初始化和相关回归测试。

## 开发注意事项

- 使用项目已有的请求入口与账号绑定逻辑，避免重复注册拦截器或绕过可信地址检查。
- 不在日志、截图、测试夹具或 Issue 中保存真实 Cookie、`access_key`、刷新凭据和账号导出内容。
- 修改请求/响应流程时检查账号切换、注销和迟到回调，不能仅验证正常登录路径。
- 通用包 API 的使用方式可查阅上游包文档；本项目行为以当前源码和[安全说明](../../../../SECURITY.md)为准。
