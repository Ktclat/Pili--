import 'dart:io' show Platform;

import 'package:PiliPlus/common/widgets/dialog/update_dialog.dart';
import 'package:PiliPlus/http/android_release.dart';
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
import 'package:flutter/foundation.dart'
    show debugPrint, kDebugMode, visibleForTesting;
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:package_info_plus/package_info_plus.dart';

abstract final class Update {
  static Future<void>? _pending;
  static bool _showFeedback = false;

  static Future<void> checkUpdate([bool isAuto = true]) =>
      kDebugMode ? Future.value() : checkStableRelease(isAuto);

  @visibleForTesting
  static Future<void> checkStableRelease(bool isAuto) {
    if (!isAuto) _showFeedback = true;
    return _pending ??= _checkStableRelease().whenComplete(() {
      _pending = null;
      _showFeedback = false;
    });
  }

  static Future<void> _checkStableRelease() async {
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
        if (_showFeedback) SmartDialog.showToast('暂无正式发布版本');
        return;
      }
      final release = ReleaseInfo.fromLatest(res.data);
      if (res.statusCode != 200 || release == null) {
        if (_showFeedback) SmartDialog.showToast('检查更新失败，请检查网络或稍后重试');
        return;
      }
      final installed = await PackageInfo.fromPlatform();
      if (!release.isNewerThan(
        installed.version,
        installedAndroidCode: Platform.isAndroid
            ? int.tryParse(installed.buildNumber)
            : null,
      )) {
        if (_showFeedback) {
          SmartDialog.showToast('已是最新版本');
        }
      } else {
        final url = await showUpdateDialog(
          release,
          checkAndroid: Platform.isAndroid
              ? () => _checkAndroidUpgrade(release, installed)
              : null,
          disableReminder: !_showFeedback
              ? () => GStorage.setting.put(SettingBoxKey.autoUpdate, false)
              : null,
        );
        if (url != null) await PageUtils.launchURL(url);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('failed to check update: $e');
      if (_showFeedback) SmartDialog.showToast('检查更新失败，请稍后重试');
    }
  }

  static Future<AndroidUpgradeResult> _checkAndroidUpgrade(
    ReleaseInfo release,
    PackageInfo installed,
  ) async {
    final manifest = await loadAndroidBuildInfo(release);
    final device = await DeviceInfoPlugin().androidInfo;
    return release.checkAndroidUpgrade(
      manifest,
      installedPackage: installed.packageName,
      installedSignature: installed.buildSignature,
      installedVersion: installed.version,
      installedCode: int.tryParse(installed.buildNumber),
      supportedAbis: device.supportedAbis,
    );
  }
}
