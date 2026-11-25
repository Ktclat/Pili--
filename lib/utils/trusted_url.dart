import 'package:PiliPlus/utils/id_utils.dart';

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

  static bool isCurrentNoteMessage({
    required Uri? source,
    required String? origin,
    required bool? mainFrame,
    required Uri? current,
  }) =>
      mainFrame == true &&
      origin == 'https://www.bilibili.com' &&
      isBilibiliNote(source) &&
      source!.removeFragment() == current?.removeFragment();

  static int? noteVideoId(Uri? uri) {
    if (!isBilibiliNote(uri)) return null;
    try {
      final id = int.tryParse(uri!.queryParameters['oid'] ?? '');
      return id != null && id > 0 ? id : null;
    } on FormatException {
      return null;
    }
  }

  /// Converts a standalone content ID to its public watch URL.
  static Uri? videoIdLink(String id) {
    if (id.length == 12 &&
        id.startsWith('BV1') &&
        id.codeUnits.skip(3).every(IdUtils.invData.containsKey)) {
      return Uri.https('www.bilibili.com', '/video/$id');
    }

    final av = IdUtils.avRegexExact.firstMatch(id);
    final aid = av == null ? null : int.tryParse(av.group(1)!);
    if (aid == null || aid <= 0 || aid >= IdUtils.MAX_AID) return null;
    return Uri.https('www.bilibili.com', '/video/${id.toLowerCase()}');
  }

  static Uri? scanLink(String value) {
    final text = value.trim();
    if (text.length > 8192 || text.contains(RegExp(r'[\x00-\x20\x7f]'))) {
      return null;
    }
    final videoLink = videoIdLink(text);
    if (videoLink != null) return videoLink;
    final uri = Uri.tryParse(text);
    return uri != null && isWebLink(uri) ? uri : null;
  }
}
