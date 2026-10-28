import 'package:flutter/foundation.dart' show immutable;
import 'package:html/parser.dart' as html;

@immutable
class MallCategory {
  final int id;
  final String name;

  const MallCategory({required this.id, required this.name});
}

@immutable
class MallProduct {
  final String id;
  final String title;
  final String? imageUrl;
  final int? priceFen;
  final String priceText;
  final String? officialUrl;
  final String? subtitle;
  final List<String> tags;

  const MallProduct({
    required this.id,
    required this.title,
    this.imageUrl,
    this.priceFen,
    required this.priceText,
    this.officialUrl,
    this.subtitle,
    this.tags = const [],
  });

  static MallProduct? fromNewItem(Object? value, {String? dayLabel}) {
    final json = mallMap(value);
    if (json == null) return null;
    return _parse(
      json,
      title: json['name'],
      image: json['img'],
      url: json['itemUrlForH5'],
      subtitle: mallText(json['brief']) ?? dayLabel,
    );
  }

  static MallProduct? fromFeedItem(Object? value) {
    final json = mallMap(value);
    if (json == null || json['type'] != 'mallitems') return null;
    return _parse(
      json,
      title: json['title'],
      image: mallList(json['imageUrls']).firstOrNull,
      url: mallList(json['jumpUrls']).firstOrNull,
      subtitle:
          mallText(json['brief']) ?? mallText(json['bottomRightCornerDesc']),
    );
  }

  static MallProduct? fromSearchItem(Object? value) {
    final json = mallMap(value);
    if (json == null) return null;
    return _parse(
      json,
      title: json['name'],
      image: json['itemsImg'],
      url: json['jumpUrlH5'],
      subtitle: mallText(json['itemsIndexDesc']),
    );
  }

  static MallProduct? _parse(
    Map<String, dynamic> json, {
    required Object? title,
    required Object? image,
    required Object? url,
    String? subtitle,
  }) {
    final id = mallInt(json['itemsId']);
    final name = mallText(title);
    if (id == null || id <= 0 || name == null) return null;
    final descriptions = mallList(json['priceDesc'])
        .map(mallText)
        .whereType<String>()
        .toList();
    final rawPrice = json['price'];
    final price = rawPrice is List ? rawPrice.firstOrNull : rawPrice;
    final fen = mallYuanToFen(descriptions.firstOrNull) ?? mallYuanToFen(price);
    final prefix = mallText(json['pricePrefix']) ?? '';
    final suffix = mallText(json['priceSuffix']) ?? '';
    final symbol = mallText(json['priceSymbol']) ?? '¥';
    final priceDescription = descriptions.isNotEmpty
        ? (suffix.isNotEmpty ? descriptions.first : descriptions.join('–'))
        : fen == null
        ? null
        : '${fen ~/ 100}.${(fen % 100).toString().padLeft(2, '0')}';
    final tagData = mallMap(json['tags']);
    final tags = <String>{};
    final presaleTag = mallText(json['preSaleTagName']);
    if (presaleTag != null) tags.add(presaleTag);
    if (tagData != null) {
      for (final key in [
        'titleTagNames',
        'promotionTagNames',
        'saleTypeTagNames',
        'serviceTagNames',
      ]) {
        tags.addAll(mallList(tagData[key]).map(mallText).whereType<String>());
      }
      final typeTag = mallText(tagData['typeAndLimitTagName']);
      if (typeTag != null) tags.add(typeTag);
    }
    final feedTags = mallMap(json['feedTag']);
    if (feedTags != null) {
      for (final group in ['frontTag', 'underTag']) {
        for (final value in mallList(feedTags[group])) {
          final tag = mallText(mallMap(value)?['title']);
          if (tag != null) tags.add(tag);
        }
      }
    }
    return MallProduct(
      id: '$id',
      title: name,
      imageUrl: mallImageUrl(image),
      priceFen: fen,
      priceText: priceDescription == null
          ? '价格待确认'
          : '$prefix$symbol$priceDescription$suffix',
      officialUrl: mallOfficialUrl(url),
      subtitle: subtitle,
      tags: List.unmodifiable(tags),
    );
  }
}

@immutable
class MallPage {
  final List<MallProduct> items;
  final List<MallCategory> categories;
  final int page;
  final int? total;
  final bool hasNext;

  const MallPage({
    required this.items,
    this.categories = const [],
    required this.page,
    this.total,
    required this.hasNext,
  });

  factory MallPage.fromNewItems(Map<String, dynamic> json) {
    final page = mallInt(json['pageNum']);
    final size = mallInt(json['pageSize']);
    final total = mallInt(json['total']);
    if (page == null || page < 1 || size == null || size < 1 || total == null) {
      throw const FormatException('Missing mall pagination');
    }
    final days = json['days'];
    if (days is! List) {
      throw const FormatException('Missing mall items');
    }
    final items = <MallProduct>[];
    final ids = <String>{};
    var rawCount = 0;
    for (final dayValue in days) {
      final day = mallMap(dayValue);
      if (day == null) continue;
      final products = mallList(day['presaleItems']);
      rawCount += products.length;
      for (final value in products) {
        final product = MallProduct.fromNewItem(
          value,
          dayLabel: mallText(day['dayNO']),
        );
        if (product != null && ids.add(product.id)) items.add(product);
      }
    }
    if (rawCount > 0 && items.isEmpty) {
      throw const FormatException('Unrecognized mall items');
    }
    final categories = <MallCategory>[];
    final categoryIds = <int>{};
    for (final value in mallList(json['cateTabs'])) {
      final category = mallMap(value);
      if (category == null) continue;
      final id = mallInt(category['cateType']);
      final name = mallText(category['cateName']);
      if (id != null && id >= 0 && name != null && categoryIds.add(id)) {
        categories.add(MallCategory(id: id, name: name));
      }
    }
    return MallPage(
      items: List.unmodifiable(items),
      categories: List.unmodifiable(categories),
      page: page,
      total: total,
      hasNext: items.isNotEmpty && page * size < total,
    );
  }

  factory MallPage.fromFeed(
    Map<String, dynamic> json, {
    required int requestedPage,
    required int pageSize,
    List<MallCategory> categories = const [],
  }) {
    final list = json['list'];
    if (list is! List) throw const FormatException('Missing mall feed');
    final items = _products(list, MallProduct.fromFeedItem);
    return MallPage(
      items: items,
      categories: categories,
      page: requestedPage,
      // Feed total is the number returned in this batch, not a global count.
      // This follows the official feed's list.length < pageSize stop condition.
      hasNext: list.length >= pageSize && items.isNotEmpty,
    );
  }

  factory MallPage.fromSearch(
    Map<String, dynamic> json, {
    required int requestedPage,
  }) {
    final list = json['list'];
    final hasNext = json['hasNextPage'];
    if (list is! List || hasNext is! bool) {
      throw const FormatException('Missing mall search pagination');
    }
    final items = _products(list, MallProduct.fromSearchItem);
    return MallPage(
      items: items,
      // The search API's pageNum is the number of pages, not the current page.
      page: requestedPage,
      total: mallInt(json['numResults']),
      hasNext: hasNext && items.isNotEmpty,
    );
  }

  static List<MallProduct> _products(
    List<dynamic> list,
    MallProduct? Function(Object?) parse,
  ) {
    final items = <MallProduct>[];
    final ids = <String>{};
    for (final value in list) {
      final product = parse(value);
      if (product != null && ids.add(product.id)) items.add(product);
    }
    if (list.isNotEmpty && items.isEmpty) {
      throw const FormatException('Unrecognized mall products');
    }
    return List.unmodifiable(items);
  }
}

@immutable
class MallProductDetail {
  final MallProduct product;
  final List<String> images;
  final String? description;
  final Map<String, String> properties;
  final List<String> descriptionImages;

  const MallProductDetail({
    required this.product,
    this.images = const [],
    this.description,
    this.properties = const {},
    this.descriptionImages = const [],
  });

  factory MallProductDetail.fromJson(Map<String, dynamic> json) {
    final price = mallText(json['price']);
    final maxPrice = mallText(json['maxPrice']);
    final images = mallList(json['img'])
        .map(mallImageUrl)
        .whereType<String>()
        .toList();
    final id = mallInt(json['itemsId']);
    final product = MallProduct._parse(
      {
        ...json,
        'pricePrefix': '商品价',
        'priceDesc': [
          ?price,
          if (maxPrice != null && maxPrice != price) maxPrice,
        ],
        'priceSuffix': '',
      },
      title: json['name'],
      image: images.firstOrNull,
      url: id == null
          ? null
          : 'https://mall.bilibili.com/neul-next/detailuniversal/detail.html'
                '?page=detailuniversal_detail&itemsId=$id',
      subtitle: mallText(json['brief']),
    );
    if (product == null) throw const FormatException('Missing mall product');
    final properties = <String, String>{};
    void addProperty(String key, Object? value) {
      final text = mallText(value);
      if (text != null) properties[key] = text;
    }

    addProperty('店铺', mallMap(json['shopInfoVO'])?['shopName']);
    addProperty('品牌', json['brandName']);
    addProperty('作品', json['ipRightName']);
    for (final value in mallList(json['attrList'])) {
      final attr = mallMap(value);
      final name = mallText(attr?['attrName']);
      if (name == null) continue;
      final raw = attr?['attrValue'];
      addProperty(
        name,
        raw is List ? raw.map(mallText).whereType<String>().join('、') : raw,
      );
    }
    addProperty(
      '官方活动',
      mallMap(json['multiDiscountActivityInfoVO'])?['benefitName'],
    );
    // depositPrice is yuan; the neighboring numeric deposit field is fen.
    final deposit = mallYuanToFen(
      mallMap(json['itemsDepositVO'])?['depositPrice'],
    );
    if (deposit != null && deposit > 0) {
      properties['定金'] =
          '¥${deposit ~/ 100}.${(deposit % 100).toString().padLeft(2, '0')}（非全款）';
    }
    addProperty('预计发货', json['presaleDeliveryTimeStr']);
    final texts = <String>[];
    final descriptionImages = <String>{};
    final desc = mallMap(json['detailDescVO']);
    for (final section in mallList(desc?['descList'])) {
      final block = mallMap(section);
      final title = mallText(block?['title']);
      if (title != null) texts.add(title);
      for (final value in mallList(block?['contentList'])) {
        final content = mallMap(value);
        if (content?['type'] == 0) {
          final text = mallText(content?['content']);
          if (text != null) texts.add(text);
        } else if (content?['type'] == 1) {
          final image = mallImageUrl(content?['content']);
          if (image != null) descriptionImages.add(image);
        }
      }
    }
    if (texts.isEmpty && descriptionImages.isEmpty) {
      final markup = mallText(json['mobileDesc']) ?? mallText(json['pcDesc']);
      if (markup != null) {
        final document = html.parse(markup);
        for (final element in document.querySelectorAll('script, style')) {
          element.remove();
        }
        final text = mallText(document.body?.text);
        if (text != null) texts.add(text);
        for (final element in document.querySelectorAll('img')) {
          final image = mallImageUrl(element.attributes['src']);
          if (image != null) descriptionImages.add(image);
        }
      }
    }
    return MallProductDetail(
      product: product,
      images: List.unmodifiable(images),
      description: texts.isEmpty ? null : texts.join('\n\n'),
      properties: Map.unmodifiable(properties),
      descriptionImages: List.unmodifiable(descriptionImages),
    );
  }
}

Map<String, dynamic>? mallMap(Object? value) {
  if (value is! Map) return null;
  return {
    for (final entry in value.entries)
      if (entry.key is String) entry.key as String: entry.value,
  };
}

List<dynamic> mallList(Object? value) => value is List ? value : const [];

String? mallText(Object? value) {
  if (value is! String) return null;
  final text = value.trim();
  return text.isEmpty ? null : text;
}

int? mallInt(Object? value) {
  if (value is int) return value;
  if (value is String) return int.tryParse(value);
  return null;
}

/// The verified mall feeds express prices in yuan. Parse decimal digits rather
/// than multiplying a double, so values such as 10.35 remain exactly 1035 fen.
int? mallYuanToFen(Object? value) {
  if (value is! String && value is! num) return null;
  final match = RegExp(r'^(\d+)(?:\.(\d{1,2}))?$').firstMatch('$value'.trim());
  if (match == null) return null;
  final whole = int.tryParse(match[1]!);
  if (whole == null || whole > 1000000000) return null;
  final fraction = (match[2] ?? '').padRight(2, '0');
  return whole * 100 + int.parse(fraction);
}

String? mallImageUrl(Object? value) {
  final text = mallText(value);
  if (text == null) return null;
  final uri = Uri.tryParse(text.startsWith('//') ? 'https:$text' : text);
  if (uri == null ||
      (uri.scheme != 'https' && uri.scheme != 'http') ||
      uri.userInfo.isNotEmpty ||
      (uri.host != 'hdslb.com' &&
          !uri.host.endsWith('.hdslb.com') &&
          uri.host != 'biliimg.com' &&
          !uri.host.endsWith('.biliimg.com'))) {
    return null;
  }
  return uri.replace(scheme: 'https', port: 443).toString();
}

String? mallOfficialUrl(Object? value) {
  final text = mallText(value);
  if (text == null) return null;
  final uri = Uri.tryParse(text);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.userInfo.isNotEmpty ||
      uri.port != 443 ||
      uri.host != 'mall.bilibili.com') {
    return null;
  }
  return uri.toString();
}
