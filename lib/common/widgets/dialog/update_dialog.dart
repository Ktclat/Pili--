import 'dart:io' show Platform;

import 'package:PiliPlus/common/constants.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:PiliPlus/utils/release_info.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:material_ui/material_ui.dart';

/// Returns the user-selected URL, or null if the dialog was closed.
Future<String?> showUpdateDialog(
  ReleaseInfo release, {
  Future<AndroidUpgradeResult> Function()? checkAndroid,
  VoidCallback? disableReminder,
}) {
  const tag = 'appUpdate';
  bool closed = false;
  bool checking = false;
  AndroidUpgradeStatus? status;

  void close([String? url]) {
    if (closed) return;
    closed = true;
    SmartDialog.dismiss<String>(tag: tag, result: url);
  }

  return SmartDialog.show<String>(
    tag: tag,
    animationType: SmartAnimationType.centerFade_otherSlide,
    onDismiss: () => closed = true,
    builder: (_) => StatefulBuilder(
      builder: (context, setState) {
        Future<void> verify() async {
          if (closed || checking || checkAndroid == null) return;
          setState(() => checking = true);
          AndroidUpgradeResult result;
          try {
            result = await checkAndroid();
          } catch (_) {
            result = const AndroidUpgradeResult(
              AndroidUpgradeStatus.unavailable,
            );
          }
          if (closed || !context.mounted) return;
          if (result.status == AndroidUpgradeStatus.verified &&
              result.downloadUrl != null) {
            close(result.downloadUrl);
            return;
          }
          setState(() {
            checking = false;
            status = result.status;
          });
        }

        final message = switch (status) {
          AndroidUpgradeStatus.signerMismatch => '当前安装包的签名与正式版不同，Android 无法覆盖安装。请在「设置 → 关于 → 导入/导出所有数据」导出备份，离线视频需另行保留。',
          AndroidUpgradeStatus.packageMismatch =>
            '正式版使用不同的应用包名，Android 会将其作为另一个应用安装。',
          AndroidUpgradeStatus.unsupportedAbi => '这个版本没有适用于当前设备架构的 APK。',
          AndroidUpgradeStatus.notNewer => '当前安装版本相同或更高。',
          AndroidUpgradeStatus.unavailable => '暂时无法核对安装包的更新信息。可以重试或查看发布页。',
          _ => null,
        };
        final platform = Platform.operatingSystem;
        Widget download(String extension) => TextButton(
          onPressed: () => close(
            release.platformDownloadUrl(platform, extension: extension) ??
                release.pageUrl,
          ),
          child: Text(extension == 'tar.gz' ? 'targz' : extension),
        );

        return AlertDialog(
          title: Text('发现新版本 ${release.data['tag_name']}'),
          content: checking
              ? const Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 12,
                  children: [
                    Text('正在核对版本、设备架构和签名…'),
                    LinearProgressIndicator(),
                  ],
                )
              : message != null
              ? SingleChildScrollView(child: Text(message))
              : SizedBox(
                  height: 280,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(release.data['body']?.toString() ?? ''),
                        TextButton(
                          onPressed: () => PageUtils.launchURL(
                            '${Constants.sourceCodeUrl}/commits/main',
                          ),
                          child: const Text('查看完整更新记录'),
                        ),
                      ],
                    ),
                  ),
                ),
          actions: [
            if (disableReminder != null && !checking && message == null)
              TextButton(
                onPressed: () {
                  close();
                  disableReminder();
                },
                child: const Text('不再提醒'),
              ),
            TextButton(onPressed: close, child: const Text('取消')),
            if (!checking)
              if (message != null) ...[
                if (status == AndroidUpgradeStatus.signerMismatch)
                  TextButton(
                    onPressed: () => close(
                      '${Constants.sourceCodeUrl}/blob/main/docs/INSTALL.md#旧测试签名迁移',
                    ),
                    child: const Text('迁移说明'),
                  ),
                TextButton(
                  onPressed: () => close(release.pageUrl),
                  child: const Text('查看发布页'),
                ),
                if (status == AndroidUpgradeStatus.unavailable)
                  TextButton(onPressed: verify, child: const Text('重试')),
              ] else if (checkAndroid != null)
                TextButton(onPressed: verify, child: const Text('下载更新'))
              else if (Platform.isWindows &&
                  release.platformDownloadUrl(platform) != null) ...[
                download('zip'),
                download('exe'),
              ] else if (Platform.isLinux &&
                  release.platformDownloadUrl(platform) != null) ...[
                download('rpm'),
                download('deb'),
                download('tar.gz'),
              ] else
                TextButton(
                  onPressed: () => close(release.pageUrl),
                  child: const Text('查看发布页'),
                ),
          ],
        );
      },
    ),
  );
}
