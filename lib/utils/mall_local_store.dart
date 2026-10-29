import 'dart:async';

import 'package:PiliPlus/models/mall/mall.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive.dart';

@immutable
class MallSavedProduct {
  const MallSavedProduct({required this.product, required this.savedAt});

  final MallProduct product;
  final DateTime savedAt;

  Map<String, Object?> toJson() => {
    'id': product.id,
    'title': product.title,
    'image': product.imageUrl,
    'priceFen': product.priceFen,
    'priceText': product.priceText,
    'officialUrl': product.officialUrl,
    'subtitle': product.subtitle,
    'tags': product.tags,
    'savedAt': savedAt.millisecondsSinceEpoch,
  };

  static MallSavedProduct? fromJson(Object? value) {
    final json = mallMap(value);
    if (json == null) return null;
    final id = mallText(json['id']);
    final title = _boundedText(json['title'], 200);
    final price = _boundedText(json['priceText'], 80);
    final time = mallInt(json['savedAt']);
    if (id == null ||
        !RegExp(r'^[1-9]\d{0,19}$').hasMatch(id) ||
        title == null ||
        price == null ||
        time == null ||
        time < 0 ||
        time > 8640000000000000) {
      return null;
    }
    final fen = mallInt(json['priceFen']);
    return MallSavedProduct(
      product: MallProduct(
        id: id,
        title: title,
        imageUrl: mallImageUrl(json['image']),
        priceFen: fen != null && fen >= 0 && fen <= 100000000000 ? fen : null,
        priceText: price,
        officialUrl: mallOfficialUrl(json['officialUrl']),
        subtitle: _boundedText(json['subtitle'], 200),
        tags: List.unmodifiable(
          mallList(json['tags'])
              .take(4)
              .map((tag) => _boundedText(tag, 32))
              .whereType<String>(),
        ),
      ),
      savedAt: DateTime.fromMillisecondsSinceEpoch(time),
    );
  }

  static String? _boundedText(Object? value, int length) {
    final text = mallText(value);
    return text == null ? null : String.fromCharCodes(text.runes.take(length));
  }
}

class _MallWriteQueue {
  Future<void>? pending;
}

class MallFavoriteLimitException implements Exception {
  const MallFavoriteLimitException();
}

/// App-local snapshots. No account credentials, network requests or cloud sync.
/// A shared per-box queue also protects updates from separate mall routes.
class MallLocalStore extends ChangeNotifier {
  MallLocalStore({Box<dynamic>? box, DateTime Function()? clock})
    : _box = box,
      _clock = clock ?? DateTime.now,
      _queue = box == null
          ? _MallWriteQueue()
          : (_queues[box] ??= _MallWriteQueue()) {
    _read();
    _subscription = box?.watch(key: dataKey).listen((_) {
      if (_disposed) return;
      _read();
      notifyListeners();
    });
  }

  static const dataKey = 'libraryV1';
  static const favoriteLimit = 200;
  static const historyLimit = 100;
  static final _queues = Expando<_MallWriteQueue>();
  final Box<dynamic>? _box;
  final DateTime Function() _clock;
  final _MallWriteQueue _queue;
  StreamSubscription<BoxEvent>? _subscription;
  List<MallSavedProduct> _favorites = const [];
  List<MallSavedProduct> _history = const [];
  bool _recordHistory = true;
  bool _disposed = false;

  List<MallSavedProduct> get favorites => _favorites;
  List<MallSavedProduct> get history => _history;
  bool get recordHistory => _recordHistory;
  bool isFavorite(String id) => _favorites.any((item) => item.product.id == id);

  void _read() {
    if (_box == null) return;
    final json = mallMap(_box.get(dataKey));
    if (json?['version'] != 1) {
      _favorites = const [];
      _history = const [];
      _recordHistory = true;
      return;
    }
    List<MallSavedProduct> entries(Object? value, int limit) {
      final ids = <String>{};
      return List.unmodifiable(
        mallList(value)
            .take(limit)
            .map(MallSavedProduct.fromJson)
            .whereType<MallSavedProduct>()
            .where((item) => ids.add(item.product.id)),
      );
    }

    _favorites = entries(json?['favorites'], favoriteLimit);
    _history = entries(json?['history'], historyLimit);
    _recordHistory = json?['recordHistory'] != false;
  }

  Future<void> _write(VoidCallback mutate) {
    if (_disposed) return Future.error(StateError('Mall store is disposed'));
    Future<void> apply() async {
      _read();
      final favorites = _favorites;
      final history = _history;
      final recording = _recordHistory;
      mutate();
      if (identical(_favorites, favorites) &&
          identical(_history, history) &&
          _recordHistory == recording) {
        return;
      }
      try {
        if (_box case final box?) {
          await box.put(dataKey, {
            'version': 1,
            'favorites': _favorites.map((item) => item.toJson()).toList(),
            'history': _history.map((item) => item.toJson()).toList(),
            'recordHistory': _recordHistory,
          });
        }
      } catch (_) {
        _favorites = favorites;
        _history = history;
        _recordHistory = recording;
        rethrow;
      }
      if (!_disposed) notifyListeners();
    }

    final operation = _queue.pending?.then((_) => apply()) ?? apply();
    _queue.pending = operation.then<void>((_) {}, onError: (Object _) {});
    return operation;
  }

  MallSavedProduct _snapshot(MallProduct product) {
    final item = MallSavedProduct.fromJson(
      MallSavedProduct(product: product, savedAt: _clock()).toJson(),
    );
    if (item == null) throw ArgumentError('Invalid local mall product');
    return item;
  }

  Future<void> toggleFavorite(MallProduct product) => _write(() {
    if (isFavorite(product.id)) {
      _favorites = List.unmodifiable(
        _favorites.where((item) => item.product.id != product.id),
      );
    } else {
      if (_favorites.length >= favoriteLimit) {
        throw const MallFavoriteLimitException();
      }
      _favorites = List.unmodifiable([
        _snapshot(product),
        ..._favorites,
      ]);
    }
  });

  Future<void> visit(MallProduct product) => _write(() {
    if (!_recordHistory) return;
    _history = List.unmodifiable([
      _snapshot(product),
      ..._history
          .where((item) => item.product.id != product.id)
          .take(historyLimit - 1),
    ]);
  });

  Future<void> refreshProduct(MallProduct product) => _write(() {
    if (!_favorites.any((item) => item.product.id == product.id) &&
        !_history.any((item) => item.product.id == product.id)) {
      return;
    }
    final fresh = _snapshot(product).product;
    List<MallSavedProduct> refresh(List<MallSavedProduct> items) =>
        List.unmodifiable(
          items.map(
            (item) => item.product.id == product.id
                ? MallSavedProduct(product: fresh, savedAt: item.savedAt)
                : item,
          ),
        );
    _favorites = refresh(_favorites);
    _history = refresh(_history);
  });

  Future<void> removeFavorite(String id) => _write(() {
    _favorites = List.unmodifiable(
      _favorites.where((item) => item.product.id != id),
    );
  });

  Future<void> removeHistory(String id) => _write(() {
    _history = List.unmodifiable(
      _history.where((item) => item.product.id != id),
    );
  });

  Future<void> clearFavorites() => _write(() => _favorites = const []);
  Future<void> clearHistory() => _write(() => _history = const []);
  Future<void> setRecordHistory(bool value) =>
      _write(() => _recordHistory = value);

  @override
  void dispose() {
    _disposed = true;
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}
