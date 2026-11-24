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
  static final _trailing = RegExp(r'[.,!?;:，。！？；：、）)】\]》〉」』]+$');

  static List<Uri> parse(String text) {
    if (text.isEmpty ||
        text.length > maxTextLength ||
        text.contains(RegExp(r'[\x00-\x08\x0b-\x1f\x7f]'))) {
      return const [];
    }
    final result = <Uri>[];
    final seen = <String>{};
    for (final match in _candidate.allMatches(text)) {
      final id = match.namedGroup('id');
      final uri = id == null ? _parseLink(match.group(0)!) : _videoLink(id);
      if (uri != null && seen.add(uri.toString())) result.add(uri);
      if (result.length == 8) break;
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

  static Uri? _videoLink(String raw) {
    final id = raw.toLowerCase().startsWith('bv')
        ? 'BV${raw.substring(2)}'
        : raw.toLowerCase();
    if (id.startsWith('av') && (int.tryParse(id.substring(2)) ?? 0) <= 0) {
      return null;
    }
    return Uri.https('www.bilibili.com', '/video/$id');
  }
}
