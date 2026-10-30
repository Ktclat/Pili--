/// Central policy for account-bearing requests and scanned links.
abstract final class TrustedUrl {
  static bool isBilibili(Uri uri) =>
      uri.scheme == 'https' &&
      uri.userInfo.isEmpty &&
      uri.port == 443 &&
      (uri.host == 'bilibili.com' || uri.host.endsWith('.bilibili.com'));

  static bool isWebLink(Uri uri) =>
      (uri.scheme == 'https' || uri.scheme == 'http') &&
      uri.host.isNotEmpty &&
      uri.userInfo.isEmpty;

  static bool isBilibiliNote(Uri? uri) =>
      uri != null &&
      isBilibili(uri) &&
      uri.host == 'www.bilibili.com' &&
      uri.path == '/h5/note-app';

  static int? noteVideoId(Uri? uri) {
    if (!isBilibiliNote(uri)) return null;
    try {
      final id = int.tryParse(uri!.queryParameters['oid'] ?? '');
      return id != null && id > 0 ? id : null;
    } on FormatException {
      return null;
    }
  }

  static Uri? scanLink(String value) {
    final text = value.trim();
    if (text.length > 8192 || text.contains(RegExp(r'[\x00-\x20\x7f]'))) {
      return null;
    }
    if (RegExp(r'^BV[0-9A-Za-z]{10}$').hasMatch(text)) {
      return Uri.https('www.bilibili.com', '/video/$text');
    }
    if (RegExp(r'^av[0-9]+$', caseSensitive: false).hasMatch(text)) {
      return Uri.https('www.bilibili.com', '/video/${text.toLowerCase()}');
    }
    final uri = Uri.tryParse(text);
    return uri != null && isWebLink(uri) ? uri : null;
  }
}
