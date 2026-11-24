import 'dart:async';

import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models/common/rcmd_source.dart';
import 'package:PiliPlus/pages/rcmd/controller.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

class _Settings extends Fake implements Box<dynamic> {
  final stored = <String, dynamic>{};

  @override
  dynamic get(dynamic key, {dynamic defaultValue}) =>
      stored[key] ?? defaultValue;
}

class _ControlledFeed extends RcmdController {
  final requests = <Completer<LoadingState>>[];

  @override
  Future<LoadingState> customGetData() {
    final request = Completer<LoadingState>();
    requests.add(request);
    return request.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final settings = _Settings();
  setUpAll(() => GStorage.setting = settings);
  setUp(settings.stored.clear);

  test('recommendation source reads current and legacy settings', () {
    expect(Pref.rcmdSource, RcmdSource.app);
    settings.stored[SettingBoxKey.appRcmd] = false;
    expect(Pref.rcmdSource, RcmdSource.web);
    for (final invalidValue in ['2', 1.5, -1, 99]) {
      settings.stored[SettingBoxKey.rcmdSource] = invalidValue;
      expect(Pref.rcmdSource, RcmdSource.web);
    }
    settings.stored[SettingBoxKey.rcmdSource] = RcmdSource.desktop.index;
    expect(Pref.rcmdSource, RcmdSource.desktop);
  });

  test('a source change ignores prior page and refresh responses', () async {
    final feed = _ControlledFeed();
    addTearDown(feed.onClose);
    final initial = feed.onRefresh();
    feed.requests.single.complete(const Success(['first']));
    await initial;
    final more = feed.onLoadMore();
    final web = feed.changeSource(.web);
    final desktop = feed.changeSource(.desktop);
    expect(feed.requests, hasLength(4));
    feed.requests[1].complete(const Success(['old page']));
    await more;
    expect(feed.isLoading, isTrue);
    expect(feed.loadingState.value, isA<Loading>());
    feed.requests[3].complete(const Success(['desktop']));
    await desktop;
    feed.requests[2].complete(const Error('late failure'));
    await web;
    expect(feed.loadingState.value.data, ['desktop']);
    expect(feed.lastRefreshAt, isNull);
    expect(feed.page, 1);
  });

  test(
    'refresh errors keep an existing feed and are visible on a new source',
    () async {
      final feed = _ControlledFeed();
      addTearDown(feed.onClose);
      final initial = feed.onRefresh();
      feed.requests.single.complete(const Success(['initial']));
      await initial;
      final refresh = feed.onRefresh();
      feed.requests.last.complete(const Error('failed refresh'));
      await refresh;
      expect(feed.loadingState.value.data, ['initial']);
      final replacement = feed.changeSource(.web);
      feed.requests.last.complete(const Error('unavailable'));
      await replacement;
      expect(feed.loadingState.value, const Error('unavailable'));
      expect(feed.isLoading, isFalse);
      final retry = feed.onReload();
      feed.requests.last.complete(const Success(['web']));
      await retry;
      expect(feed.loadingState.value.data, ['web']);
    },
  );
}
