import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/http/user.dart';
import 'package:PiliPlus/services/account_service.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/global_data.dart';
import 'package:PiliPlus/utils/request_utils.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:PiliPlus/utils/utils.dart';
import 'package:collection/collection.dart';
import 'package:crypto/crypto.dart' show Digest;
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

abstract final class LoginUtils {
  static Future<void> onLoginMain() async {
    final account = Accounts.main;
    if (!account.isLogin) return;
    final res = await UserHttp.userInfo(account);
    if (!identical(account, Accounts.main)) return;
    if (res case Success(:final response)) {
      RequestUtils.syncHistoryStatus();
      if (response.isLogin == true) {
        if (response != Pref.userInfoCache) {
          await GStorage.userInfo.put('userInfoCache', response);
          if (!identical(account, Accounts.main)) return;
        }
        final accountService = Get.find<AccountService>()
          ..face.value = response.face ?? '';

        if (accountService.isLogin.value) {
          accountService.isLogin.refresh();
        } else {
          accountService.isLogin.value = true;
        }

        SmartDialog.showToast('main登录成功');
      }
    } else {
      // 获取用户信息失败
      final errMsg = res.toString();
      if (errMsg == '账号未登录') {
        await Accounts.deleteAll({account});
        SmartDialog.showNotify(
          msg: '登录失败，请检查cookie是否正确，$errMsg',
          notifyType: .warning,
        );
      } else {
        SmartDialog.showToast(errMsg);
      }
    }
  }

  static void clearMainProfile() {
    GlobalData().coins = null;
    Get.find<AccountService>()
      ..face.value = ''
      ..isLogin.value = false;
  }

  static Future<void> onLogoutMain() {
    clearMainProfile();
    return GStorage.userInfo.delete('userInfoCache');
  }

  static String generateBuvid() {
    final md5Str = Digest(
      List.generate(16, (_) => Utils.random.nextInt(256)),
    ).toString().toUpperCase();
    return 'XY${md5Str[2]}${md5Str[12]}${md5Str[22]}$md5Str';
  }

  // static String getUUID() {
  //   return const Uuid().v4().replaceAll('-', '');
  // }

  // static String generateBuvid() {
  //   String uuid = getUUID() + getUUID();
  //   return 'XY${uuid.substring(0, 35).toUpperCase()}';
  // }

  static String genDeviceId() {
    // https://github.com/bilive/bilive_client/blob/2873de0532c54832f5464a4c57325ad9af8b8698/bilive/lib/app_client.ts#L62
    final time = DateTime.now();

    final List<int> bytes = [
      ...Iterable.generate(16, (_) => Utils.random.nextInt(256)),
      _dec2bcd(time.year ~/ 100),
      _dec2bcd(time.year % 100),
      _dec2bcd(time.month),
      _dec2bcd(time.day),
      _dec2bcd(time.hour),
      _dec2bcd(time.minute),
      _dec2bcd(time.second),
      ...Iterable.generate(8, (_) => Utils.random.nextInt(256)),
    ];
    final check = (bytes.sum & 0xFF).toRadixString(16).padLeft(2, '0');

    return Digest(bytes).toString() + check;
  }

  static int _dec2bcd(int dec) {
    assert(0 <= dec && dec < 100);
    return ((dec ~/ 10) << 4) | (dec % 10);
  }
}
