import 'package:flutter/foundation.dart' show immutable;

enum MallSort {
  relevance('综合排序', 'totalrank', ''),
  sales('销量优先', 'sale', ''),
  newest('最新上架', 'pubdate', ''),
  priceAscending('价格从低到高', 'price', 'asc'),
  priceDescending('价格从高到低', 'price', 'desc');

  const MallSort(this.label, this.apiType, this.apiOrder);

  final String label;
  final String apiType;
  final String apiOrder;
}

@immutable
class MallSearchOptions {
  const MallSearchOptions({
    this.sort = MallSort.relevance,
    this.minimumFen,
    this.maximumFen,
  });

  final MallSort sort;
  final int? minimumFen;
  final int? maximumFen;

  bool get hasPriceRange => minimumFen != null || maximumFen != null;
  bool get isDefault => sort == MallSort.relevance && !hasPriceRange;
  bool get isValid =>
      (minimumFen == null || minimumFen! >= 0 && minimumFen! <= 100000000000) &&
      (maximumFen == null || maximumFen! >= 0 && maximumFen! <= 100000000000) &&
      (minimumFen == null || maximumFen == null || minimumFen! <= maximumFen!);

  String get minimumYuan => _yuan(minimumFen);
  String get maximumYuan => _yuan(maximumFen);

  String get priceLabel {
    if (minimumFen != null && maximumFen != null) {
      return '¥$minimumYuan–$maximumYuan';
    }
    if (minimumFen != null) return '¥$minimumYuan起';
    if (maximumFen != null) return '¥$maximumYuan以内';
    return '价格筛选';
  }

  MallSearchOptions withSort(MallSort value) => MallSearchOptions(
    sort: value,
    minimumFen: minimumFen,
    maximumFen: maximumFen,
  );

  static String _yuan(int? fen) => fen == null
      ? ''
      : '${fen ~/ 100}.${(fen % 100).toString().padLeft(2, '0')}';

  @override
  bool operator ==(Object other) =>
      other is MallSearchOptions &&
      sort == other.sort &&
      minimumFen == other.minimumFen &&
      maximumFen == other.maximumFen;

  @override
  int get hashCode => Object.hash(sort, minimumFen, maximumFen);
}
