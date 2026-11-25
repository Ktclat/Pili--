import 'package:PiliPlus/utils/trusted_url.dart';

/// Extract public Bilibili content from shared text without network access.
/// Login/authorization links deliberately belong to the scanner's own flow.
abstract final class BiliLinkRecognition {
  static const maxTextLength = 8192;
  static const _hosts = {
    'bilibili.com',
    'www.bilibili.com',
    'm.bilibili.com',
    't.bilibili.com',
    'space.bilibili.com',
    'live.bilibili.com',
    'bangumi.bilibili.com',
    'b23.tv',
  };
  static const _schemes = {
    'video',
    'space',
    'live',
    'bangumi',
    'pgc',
    'opus',
    'article',
    'search',
  };
  // Consume complete URL tokens (including unrecognized schemes and hosts) so
  // an ID in their path or query never becomes a separate video suggestion.
  static final _candidate = RegExp(
    r'''(?<![a-zA-Z0-9_.@/\-])(?:[a-z][a-z0-9+.\-]*://|(?:[a-z0-9\-]+\.)+[a-z0-9\-]+(?=[/:?#]))[^\s<>"'`]+'''
    r'|(?<![a-zA-Z0-9_./?=&%#:@\-])(?<id>BV[0-9a-zA-Z]{10}|av[0-9]{1,19})(?![a-zA-Z0-9_])',
    caseSensitive: false,
  );
  static final _bareHost = RegExp(
    r'^(?:www\.bilibili\.com|b23\.tv)/',
    caseSensitive: false,
  );
  // A raw CJK delimiter in a content path ends the shared link. After a
  // query or fragment marker, punctuation can be part of the link's value.
  static final _pathEnd = RegExp(r'[?#，。！？；：、（）【】《》〈〉「」『』]');
  static final _trailing = RegExp(r'[.,!?;:，。！？；：、）)】\]》〉」』]+$');

  static List<Uri> parse(String text) {
    if (text.isEmpty ||
        text.length > maxTextLength ||
        text.contains(RegExp(r'[\x00-\x08\x0b-\x1f\x7f]'))) {
      return const [];
    }
    final result = <Uri>[];
    final seen = <String>{};
    var cursor = 0;
    while (cursor < text.length && result.length < 8) {
      final matches = _candidate.allMatches(text, cursor).iterator;
      if (!matches.moveNext()) break;
      final match = matches.current;
      cursor = match.end;
      final raw = match.group(0)!;
      Uri? uri;
      if (match.namedGroup('id') != null) {
        // Share captions also accept lowercase BV prefixes. The suffix is case-sensitive.
        final id = raw.toLowerCase().startsWith('bv')
            ? 'BV${raw.substring(2)}'
            : raw;
        uri = TrustedUrl.videoIdLink(id);
      } else {
        uri = _parseLink(raw);
        // Only rescan the remaining caption after recognizing a trusted link.
        // An unrelated URL may itself contain an apparent video ID after punctuation.
        if (uri == null) continue;
        final boundary = _pathEnd.firstMatch(raw);
        if (boundary != null && boundary[0] != '?' && boundary[0] != '#') {
          uri = _parseLink(raw.substring(0, boundary.start));
          cursor = match.start + boundary.end;
        }
      }
      if (uri != null && seen.add(uri.toString())) result.add(uri);
    }
    return result;
  }

  static Uri? _parseLink(String value) {
    value = value.replaceFirst(_trailing, '');
    if (_bareHost.hasMatch(value)) value = 'https://$value';
    // Uri normalizes an empty user-info marker away; inspect raw authority.
    if (RegExp(r'^[^:]+://[^/?#]*@').hasMatch(value)) return null;
    try {
      final uri = Uri.tryParse(value);
      if (uri == null ||
          uri.userInfo.isNotEmpty ||
          uri.authority.contains('@')) {
        return null;
      }
      if ((uri.scheme == 'https' || uri.scheme == 'http') &&
          _hosts.contains(uri.host) &&
          uri.port == (uri.scheme == 'https' ? 443 : 80)) {
        return uri.replace(scheme: 'https', port: 443);
      }
      if (uri.scheme == 'bilibili' &&
          _schemes.contains(uri.host) &&
          !uri.hasPort) {
        return uri;
      }
    } on FormatException {
      // Uri validates a numeric port lazily when its authority is accessed.
      return null;
    }
    return null;
  }
}
