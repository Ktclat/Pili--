import 'dart:io' show Platform;

import 'package:PiliPlus/common/constants.dart';
import 'package:PiliPlus/http/api.dart';
import 'package:PiliPlus/http/browser_ua.dart';
import 'package:PiliPlus/http/init.dart';
import 'package:PiliPlus/utils/accounts/account.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:PiliPlus/utils/release_info.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:material_ui/material_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';

abstract final class Update {
  // 检查更新
  static Future<void> checkUpdate([bool isAuto = true]) async {
    if (kDebugMode) return;
    SmartDialog.dismiss();
    try {
      final res = await Request().get(
        Api.latestApp,
        options: Options(
          headers: {'user-agent': BrowserUa.mob},
          extra: {'account': const NoAccount()},
          validateStatus: (status) => status == 200 || status == 404,
        ),
      );
      if (res.statusCode == 404) {
        if (!isAuto) SmartDialog.showToast('暂无正式发布版本');
        return;
      }
      final release = ReleaseInfo.fromLatest(res.data);
      if (res.statusCode != 200 || release == null) {
        if (!isAuto) SmartDialog.showToast('检查更新失败，请检查网络或稍后重试');
        return;
      }
      final installed = await PackageInfo.fromPlatform();
      final data = release.data;
      if (!release.isNewerThan(
        installed.version,
        installedAndroidCode: Platform.isAndroid
            ? int.tryParse(installed.buildNumber)
            : null,
      )) {
        if (!isAuto) {
          SmartDialog.showToast('已是最新版本');
        }
      } else {
        SmartDialog.show(
          animationType: SmartAnimationType.centerFade_otherSlide,
          builder: (context) {
            final colorScheme = ColorScheme.of(context);
            Widget downloadBtn(String label, {String? ext}) => TextButton(
              onPressed: () => onDownload(release, ext: ext),
              child: Text(label),
            );
            return AlertDialog(
              title: const Text('🎉 发现新版本 '),
              content: SizedBox(
                height: 280,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${data['tag_name']}',
                        style: const TextStyle(fontSize: 20),
                      ),
                      const SizedBox(height: 8),
                      Text('${data['body']}'),
                      TextButton(
                        onPressed: () => PageUtils.launchURL(
                          '${Constants.sourceCodeUrl}/commits/main',
                        ),
                        child: Text(
                          "点此查看完整更新(即commit)内容",
                          style: TextStyle(color: colorScheme.primary),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                if (isAuto)
                  TextButton(
                    onPressed: () {
                      SmartDialog.dismiss();
                      GStorage.setting.put(SettingBoxKey.autoUpdate, false);
                    },
                    child: Text(
                      '不再提醒',
                      style: TextStyle(color: colorScheme.outline),
                    ),
                  ),
                TextButton(
                  onPressed: SmartDialog.dismiss,
                  child: Text(
                    '取消',
                    style: TextStyle(color: colorScheme.outline),
                  ),
                ),
                if (Platform.isWindows &&
                    release.platformDownloadUrl('windows') != null) ...[
                  downloadBtn('zip', ext: 'zip'),
                  downloadBtn('exe', ext: 'exe'),
                ] else if (Platform.isLinux &&
                    release.platformDownloadUrl('linux') != null) ...[
                  downloadBtn('rpm', ext: 'rpm'),
                  downloadBtn('deb', ext: 'deb'),
                  downloadBtn('targz', ext: 'tar.gz'),
                ] else
                  downloadBtn(Platform.isAndroid ? '下载更新' : '查看发布页'),
              ],
            );
          },
        );
      }
    } catch (e) {
      if (kDebugMode) debugPrint('failed to check update: $e');
      if (!isAuto) SmartDialog.showToast('检查更新失败，请稍后重试');
    }
  }

  static Future<void> onDownload(ReleaseInfo release, {String? ext}) async {
    SmartDialog.dismiss();
    var url = release.pageUrl;
    if (Platform.isAndroid) {
      try {
        final device = await DeviceInfoPlugin().androidInfo;
        url = release.androidDownloadUrl(device.supportedAbis) ?? url;
      } catch (e) {
        if (kDebugMode) debugPrint('Cannot select an Android ABI: $e');
      }
    } else {
      url =
          release.platformDownloadUrl(
            Platform.operatingSystem,
            extension: ext,
          ) ??
          url;
    }
    await PageUtils.launchURL(url);
  }
}
