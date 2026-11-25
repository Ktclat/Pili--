# 扫码授权、分享与剪贴板

[项目首页](../README.md) · [安装说明](INSTALL.md) · [安全说明](../SECURITY.md)

## 使用入口

从 0.6.3+13 起，首页和「我的」右上角默认显示「扫一扫」。可用相机或相册识别二维码，再点选内容打开。为自己的网页或 TV 登录时，扫描待登录设备上的二维码，核对账号、目标应用和登录位置后确认授权。登录位置有差异时需要再次确认。同一部手机上可点「粘贴登录链接」。要登录 Pili-- 自身，请使用登录页。

点「扫一扫」右上角的链接图标打开「识别链接」，输入或粘贴分享文案、B 站内容链接、b23.tv 短链或 BV/av 号。多个结果可逐项选择，点选短链后才联网解析。也可在设置中将「识别链接」直接显示在首页或「我的」。[编辑右上角按钮](INSTALL.md#编辑首页和我的右上角按钮)

Android 可从其他 App 的系统分享面板选择 Pili--，启动后在识别结果中选取内容。应用已打开时也可接收分享。

## 让另一个 Android App 跳转登录（0.6.1 开发版）

调用方需要先向哔哩哔哩发起自己的网页或 TV 扫码登录请求，并保留原有的结果查询流程。用户点击登录时，调用方可用下例打开 Pili-- 的原生授权页。`qrUrl` 是官方返回的完整二维码 HTTPS 链接。

```kotlin
val intent = Intent("io.github.ktclat.piliminus.action.AUTHORIZE_LOGIN", Uri.parse(qrUrl))
    .setPackage("io.github.ktclat.piliminus")
try {
    startActivity(intent)
} catch (_: ActivityNotFoundException) {
    // 无法打开 Pili-- 时，继续显示本次请求的二维码。
    showLoginQrCode(qrUrl)
}
```

示例中的 `showLoginQrCode` 代表调用方已有的二维码界面。专用 action 由支持此功能的 Pili-- 版本声明，因此未安装或仅安装旧版时可以直接回到二维码。指定包名可在与 PiliPlus 同时安装时准确打开 Pili--。写死上游包名的 App 需要增加此选项。

已使用标准 `Intent.ACTION_VIEW` 的调用方也可以把相同的官方 HTTPS 链接定向交给新版 Pili--。这种方式同样会匹配只支持普通网页的旧版，因此新接入建议使用上面的专用 action。

用户先在 Pili-- 核对账号和登录请求，确认后切回原 App。调用方以哔哩哔哩返回的登录状态为准，用户返回或关闭授权页都不能作为登录成功的依据。Pili-- 只向官方提交本次授权，不通过 Intent 传递账号 Cookie 或 access token。需要开放平台 OAuth 回调的 App 应继续使用其登记的授权流程。

## 开关与读取边界

| 设置 → 隐私设置 | 默认行为 |
| --- | --- |
| 接收其他 App 分享的 B 站链接 | 开启；关闭后忽略收到的分享 |
| 自动识别剪贴板中的 B 站链接 | 关闭；开启后应用进入前台时读取，确认后打开 |

手动粘贴仅在点击时读取，可独立于自动识别使用。同一段剪贴板内容只提示一次。扫码、授权和手动输入页面会暂停自动提示。

分享正文、剪贴板正文和登录码在内存中处理。

## 授权支持与限制

支持当前 `account.bilibili.com/h5/account-h5/auth/scan-web`、旧版 Passport 网页码和已核对的 TV/HD 授权码。严格验证 HTTPS 主机、路径、密钥及重复参数，忽略二维码提供的回调地址；普通分享识别不接收登录授权链接。

确认请求只发往固定的 Passport 官方端点，绑定扫码时的账号，不跨源重定向、不自动重试写请求，不把远端登录返回的 Cookie 安装到当前账号。关闭、过期或账号变化后不再提交；已经发出的授权无法通过关闭页面撤回。若网络超时，先到待登录设备核对结果，避免重复授权。

遇到手机号或设备环境验证时，请按提示使用哔哩哔哩官方 App 完成。

## 契约参考与验证

仅参考官方公开前端的数据契约，自行实现 Flutter 页面与请求，未打包官方 JS。参考 [account-h5 入口脚本](https://s1.hdslb.com/bfs/static/2233-monorepo/account-h5/static/js/index.eb5c0d23.js)、[当前扫码页面](https://s1.hdslb.com/bfs/static/2233-monorepo/account-h5/static/js/async/542.dae0ac19.js)、[接口声明](https://s1.hdslb.com/bfs/static/2233-monorepo/account-h5/static/js/async/2202.d6259a17.js)及 Passport 旧版页面。

自动测试使用模拟账号和响应，构建与设备测试按提交记录。[验证记录](VALIDATION.md)
