import 'package:PiliPlus/http/live.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models_new/live/live_config_plugs/data.dart';
import 'package:PiliPlus/models_new/live/live_fans_medal/data.dart';
import 'package:PiliPlus/models_new/live/live_fans_medal/item.dart';
import 'package:PiliPlus/pages/common/common_list_controller.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/accounts/account.dart';
import 'package:PiliPlus/utils/extension/get_ext.dart';
import 'package:get/get.dart' show Get, RxnInt;

class FansMedalController
    extends CommonListController<FansMedalData, FansMedalItem> {
  FansMedalController(this.account);
  final Account account;
  // A new login session can use the same UID with a different cookie jar.
  static final _accountTags = Expando<String>();
  static int _nextTag = 0;
  static FansMedalController forAccount(Account account) => Get.putOrFind(
    () => FansMedalController(account),
    tag: _accountTags[account] ??= 'medal-${_nextTag++}',
  );

  bool get isCurrent =>
      !isClosed && account.isLogin && identical(Accounts.main, account);
  final count = RxnInt();

  ConfigPlusData? config;

  Future<bool> getConfigPlus() async {
    if (!isCurrent) return false;
    final res = await LiveHttp.liveConfigPlugs(account: account);
    if (!isCurrent) return false;
    if (res case Success(:final response)) {
      config = response;
      return true;
    } else {
      res.toast();
      return false;
    }
  }

  Future<bool> setConfigPlus({
    required String key,
    required bool status,
  }) async {
    if (!isCurrent) return false;
    final res = await LiveHttp.liveEditPlugs(
      account: account,
      key: key,
      status: status ? 1 : 0,
    );
    if (!isCurrent) return false;
    if (res.isSuccess) {
      switch (key) {
        case ConfigPlusData.kCloseSpaceMedalKey:
          config!.closeSpaceMedal = status;
        case ConfigPlusData.kOnlyShowWearingKey:
          config!.onlyShowWearing = status;
      }
      return true;
    } else {
      res.toast();
      return false;
    }
  }

  @override
  void checkIsEnd(int length) {
    final count = this.count.value;
    if (count != null && length >= count) {
      isEnd = true;
    }
  }

  @override
  List<FansMedalItem>? getDataList(FansMedalData response) {
    count.value = response.totalNumber;
    return response.list;
  }

  @override
  Future<LoadingState<FansMedalData>> customGetData() async {
    const changed = Error('账号已切换，请重新打开粉丝勋章');
    if (!isCurrent) return changed;
    final res = await LiveHttp.fansMedalPanel(account: account, page: page);
    return isCurrent ? res : changed;
  }

  Future<bool> onWear(FansMedalItem item, {bool refresh = true}) async {
    if (!isCurrent) return false;
    final res = await LiveHttp.wearFansMedal(
      account: account,
      medalId: item.uinfoMedal.id!,
    );
    if (!isCurrent) return false;
    if (res.isSuccess) {
      for (final e in loadingState.value.data!) {
        if (e.medal.wearingStatus == 1) {
          e.medal.wearingStatus = 0;
          break;
        }
      }
      item.medal.wearingStatus = 1;
      if (refresh) loadingState.refresh();
      return true;
    } else {
      res.toast();
      return false;
    }
  }

  Future<bool> onTakeOff(FansMedalItem item, {bool refresh = true}) async {
    if (!isCurrent) return false;
    final res = await LiveHttp.takeOffFansMedal(account: account);
    if (!isCurrent) return false;
    if (res.isSuccess) {
      item.medal.wearingStatus = 0;
      if (refresh) loadingState.refresh();
      return true;
    } else {
      res.toast();
      return false;
    }
  }
}
