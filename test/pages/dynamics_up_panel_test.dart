import 'dart:async';

import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models/common/dynamic/dynamics_type.dart';
import 'package:PiliPlus/models/dynamics/result.dart';
import 'package:PiliPlus/models/dynamics/up.dart';
import 'package:PiliPlus/models/user/info.dart';
import 'package:PiliPlus/pages/dynamics/controller.dart';
import 'package:PiliPlus/pages/dynamics/view.dart';
import 'package:PiliPlus/pages/dynamics/widgets/up_panel.dart';
import 'package:PiliPlus/pages/dynamics_tab/controller.dart';
import 'package:PiliPlus/pages/dynamics_tab/view.dart';
import 'package:PiliPlus/pages/main/controller.dart';
import 'package:PiliPlus/services/account_service.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive_ce/hive.dart';
import 'package:material_ui/material_ui.dart';

class _Box<T> extends Fake implements Box<T> {
  final valuesByKey = <String, T>{};

  @override
  T? get(dynamic key, {T? defaultValue}) => valuesByKey[key] ?? defaultValue;
}

class _Following extends DynamicsController {
  int requests = 0;

  @override
  Future<LoadingState<FollowUpModel>> customGetData() async {
    requests++;
    if (requests > 1) {
      return Success(
        FollowUpModel.fromUpList({
          'items': [
            {'mid': 99, 'uname': '下一页的 UP 主'},
          ],
        }),
      );
    }
    return Success(
      FollowUpModel.fromJson({
        'live_users': {
          'count': 1,
          'items': [
            {'mid': 40, 'uname': '直播中的 UP 主', 'room_id': 80},
          ],
        },
        'up_list': {
          'items': [
            for (var i = 1; i <= 10; i++) {'mid': i, 'uname': '关注 $i'},
          ],
          'has_more': true,
          'offset': 'next',
        },
      }),
    );
  }
}

class _Tab extends DynamicsTabController {
  _Tab(DynamicsTabType type) : super(dynamicsType: type);

  @override
  Future<LoadingState<DynamicsDataModel>> customGetData() async =>
      Success(DynamicsDataModel.fromJson({}));
}

class _DelayedUpTab extends _Tab {
  _DelayedUpTab() : super(.up);

  final requests = <int, Completer<LoadingState<DynamicsDataModel>>>{};

  @override
  Future<LoadingState<DynamicsDataModel>> customGetData() {
    final mid = dynamicsController.hostMid;
    if (mid == -1) return super.customGetData();
    final request = Completer<LoadingState<DynamicsDataModel>>();
    requests[mid] = request;
    return request.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    GStorage.userInfo = _Box<UserInfoData>();
    GStorage.localCache = _Box<dynamic>();
    GStorage.setting = _Box<dynamic>()
      ..valuesByKey.addAll({
        'upPanelPosition': 1, // Previously pinned to the left.
        SettingBoxKey.horizontalScreen: false,
        SettingBoxKey.autoUpdate: false,
        SettingBoxKey.feedBackEnable: false,
        SettingBoxKey.expandDynLivePanel: false,
      });
  });
  setUp(() {
    Get
      ..testMode = true
      ..put(AccountService())
      ..put(MainController());
  });
  tearDown(Get.reset);

  testWidgets('upgraded dynamics page scrolls and filters from the top strip', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(390, 750)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final panel = _Following();
    Get.put<DynamicsController>(panel);
    for (final type in DynamicsTabType.values) {
      Get.put<DynamicsTabController>(_Tab(type), tag: type.name);
    }
    await tester.pumpWidget(const MaterialApp(home: DynamicsPage()));
    await tester.pumpAndSettle();

    final strip = find.byType(UpPanel);
    expect(
      tester.getTopLeft(strip).dy,
      tester.getBottomLeft(find.byType(TabBar)).dy,
    );
    expect(
      tester.getBottomLeft(strip).dy,
      tester.getTopLeft(find.byType(DynamicsTabPage).first).dy,
    );
    final scrollable = find.descendant(
      of: strip,
      matching: find.byType(Scrollable),
    );
    expect(tester.widget<Scrollable>(scrollable).axis, Axis.horizontal);
    final live = find.textContaining('Live(1)');
    final streamer = find.textContaining('直播中的 UP 主');
    expect(streamer, findsNothing);
    await tester.tap(live);
    await tester.pumpAndSettle();
    expect(streamer, findsOneWidget);
    await tester.tap(live);
    await tester.pumpAndSettle();
    expect(streamer, findsNothing);

    final next = find.textContaining('下一页的 UP 主');
    await tester.scrollUntilVisible(next, 200, scrollable: scrollable);
    await tester.pumpAndSettle();
    expect(panel.requests, 2);
    expect(panel.scrollController.offset, greaterThan(0));
    await tester.tap(next);
    await tester.pumpAndSettle();
    expect(panel.currentMid, 99);
    expect(panel.tabController.index, DynamicsTabType.up.index);

    await tester.scrollUntilVisible(
      find.textContaining('全部动态'),
      -200,
      scrollable: scrollable,
    );
    await tester.tap(find.textContaining('全部动态'));
    await tester.pumpAndSettle();
    expect(panel.currentMid, -1);
    expect(panel.tabController.index, DynamicsTabType.all.index);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'switching UPs keeps the last selected feed when the first response arrives late',
    (
      tester,
    ) async {
      final panel = Get.put<DynamicsController>(_Following());
      final up = _DelayedUpTab();
      Get.put<DynamicsTabController>(up, tag: DynamicsTabType.up.name);
      await tester.pump();

      panel
        ..onSelectUp(11)
        ..onSelectUp(22);
      expect(up.requests.keys, [11, 22]);
      up.requests[22]!.complete(
        Success(DynamicsDataModel.fromJson({'offset': 'new'})),
      );
      await tester.pump();
      up.requests[11]!.complete(
        Success(DynamicsDataModel.fromJson({'offset': 'old'})),
      );
      await tester.pump();
      expect(panel.currentMid, 22);
      expect(up.offset, 'new');
    },
  );
}
