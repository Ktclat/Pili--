import 'dart:io';

import 'package:PiliPlus/models/mall/mall.dart';
import 'package:PiliPlus/utils/mall_local_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

MallProduct _product(int id, {String? url, String price = '¥39'}) =>
    MallProduct(
      id: '$id',
      title: '商品 $id',
      priceText: price,
      officialUrl: url,
    );

class _FailingBox extends Fake implements Box<dynamic> {
  final data = <dynamic, dynamic>{};
  bool fail = true;

  @override
  dynamic get(dynamic key, {dynamic defaultValue}) => data[key] ?? defaultValue;

  @override
  Stream<BoxEvent> watch({dynamic key}) => const Stream.empty();

  @override
  Future<void> put(dynamic key, dynamic value) async {
    if (fail) throw StateError('simulated persistence failure');
    data[key] = value;
  }
}

void main() {
  late Directory directory;
  late Box<dynamic> box;
  final stores = <MallLocalStore>[];

  MallLocalStore store() {
    final value = MallLocalStore(box: box);
    stores.add(value);
    return value;
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('pili-mall-library-');
    Hive.init(directory.path);
    box = await Hive.openBox('mall');
  });
  tearDown(() async {
    for (final value in stores) {
      value.dispose();
    }
    stores.clear();
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test('favorites and special purchase links survive a full box reopen', () async {
    const link =
        'https://mall.bilibili.com/neul/index.html?page=magic-detail_detail&itemsId=1';
    final first = store();
    await first.toggleFavorite(_product(1, url: link));
    await first.visit(_product(1, url: link));
    await box.close();
    box = await Hive.openBox('mall');
    final restored = store();
    expect(restored.favorites.single.product.officialUrl, link);
    expect(restored.history.single.product.id, '1');
    expect(() => restored.favorites.clear(), throwsUnsupportedError);
  });

  test('history deduplicates visits and pause survives restart without deleting records', () async {
    final first = store();
    await first.visit(_product(1));
    await first.visit(_product(2));
    await first.visit(_product(1));
    expect(first.history.map((item) => item.product.id), ['1', '2']);
    await first.setRecordHistory(false);
    final restored = store();
    await restored.visit(_product(3));
    expect(restored.recordHistory, isFalse);
    expect(restored.history.map((item) => item.product.id), ['1', '2']);
  });

  test(
    'clearing footprints preserves favorites and the pause preference',
    () async {
      final value = store();
      await value.visit(_product(1));
      await value.toggleFavorite(_product(1));
      await value.setRecordHistory(false);
      await value.clearHistory();
      expect(value.history, isEmpty);
      expect(value.favorites, hasLength(1));
      expect(value.recordHistory, isFalse);
      await value.clearFavorites();
      expect(value.favorites, isEmpty);
    },
  );

  test(
    'separate routes serialize concurrent changes without losing a favorite',
    () async {
      final first = store();
      final second = store();
      await Future.wait([
        first.toggleFavorite(_product(1)),
        second.toggleFavorite(_product(2)),
        first.visit(_product(3)),
        second.setRecordHistory(false),
      ]);
      final restored = store();
      expect(restored.favorites.map((item) => item.product.id), ['2', '1']);
      expect(restored.history.single.product.id, '3');
      expect(restored.recordHistory, isFalse);
    },
  );

  test('an accepted save finishes after its route store is disposed', () async {
    final value = MallLocalStore(box: box);
    final saving = value.toggleFavorite(_product(1));
    value.dispose();
    await saving;
    expect(store().favorites.single.product.id, '1');
  });

  test('fresh detail updates snapshots without changing visit order or adding paused visits', () async {
    final value = store();
    await value.visit(_product(1));
    await value.visit(_product(2));
    await value.toggleFavorite(_product(1));
    final visitedAt = value.history.last.savedAt;
    await value.setRecordHistory(false);
    await value.refreshProduct(_product(1, price: '商品价¥115'));
    expect(value.favorites.single.product.priceText, '商品价¥115');
    expect(value.history.map((item) => item.product.id), ['2', '1']);
    expect(value.history.last.savedAt, visitedAt);
    await value.refreshProduct(_product(3));
    expect(value.history, hasLength(2));
  });

  test(
    'malformed rows and unsafe snapshot links cannot become actions',
    () async {
      final item = MallSavedProduct(
        product: _product(1),
        savedAt: DateTime(2026),
      ).toJson();
      await box.put(MallLocalStore.dataKey, {
        'version': 1,
        'favorites': [
          null,
          {...item, 'id': '../1'},
          {...item, 'savedAt': -1},
          {
            ...item,
            'officialUrl': 'javascript:alert(1)',
            'image': 'https://evil.test/a.png',
          },
          item,
        ],
      });
      final value = store();
      expect(value.favorites, hasLength(1));
      expect(value.favorites.single.product.officialUrl, isNull);
      expect(value.favorites.single.product.imageUrl, isNull);
    },
  );

  test('history rolls over while full favorites reject additions without data loss', () async {
    final value = MallLocalStore();
    addTearDown(value.dispose);
    for (var id = 1; id <= MallLocalStore.favoriteLimit; id++) {
      await value.toggleFavorite(_product(id));
    }
    await expectLater(
      value.toggleFavorite(_product(999)),
      throwsA(isA<MallFavoriteLimitException>()),
    );
    expect(value.favorites.last.product.id, '1');
    await value.removeFavorite('1');
    await value.toggleFavorite(_product(999));
    expect(value.favorites.first.product.id, '999');
    for (var id = 1; id <= MallLocalStore.historyLimit + 1; id++) {
      await value.visit(_product(id));
    }
    expect(value.history, hasLength(MallLocalStore.historyLimit));
    expect(value.history.last.product.id, '2');
  });

  test(
    'a failed persistence write is not reported as a successful favorite',
    () async {
      final failing = _FailingBox();
      final value = MallLocalStore(box: failing);
      addTearDown(value.dispose);
      await expectLater(value.toggleFavorite(_product(1)), throwsA(anything));
      expect(value.favorites, isEmpty);
      failing.fail = false;
      await value.toggleFavorite(_product(2));
      expect(value.favorites.single.product.id, '2');
    },
  );
}
